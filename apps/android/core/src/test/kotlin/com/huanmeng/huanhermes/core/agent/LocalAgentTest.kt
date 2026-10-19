package com.huanmeng.huanhermes.core.agent

import com.huanmeng.huanhermes.core.ssh.ExecResult
import com.huanmeng.huanhermes.core.ssh.SshException
import com.huanmeng.huanhermes.core.ssh.SshRunner
import com.huanmeng.huanhermes.core.ssh.TrileadSshRunner
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MemStore : SshServerStorage, AgentHistoryStorage {
    var raw: String? = null
    override suspend fun load() = raw
    override suspend fun save(raw: String) { this.raw = raw }
}

class FakeSsh(val log: MutableList<String>) : SshRunner {
    override fun run(command: String, timeoutMs: Long): ExecResult { log += command; return ExecResult(0, "out:$command", "") }
    override fun upload(bytes: ByteArray, remoteDir: String, remoteName: String) {}
    override fun close() {}
}

/** Scripted model: returns queued turns, records what it saw. */
class ScriptLlm(vararg turns: LlmTurn) : LlmClient {
    val queue = ArrayDeque(turns.toList())
    val seen = mutableListOf<List<AgentMessage>>()
    override suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): LlmTurn {
        seen += messages; return queue.removeFirstOrNull() ?: LlmTurn("done", emptyList())
    }
}

private fun call(id: String, name: String, vararg kv: Pair<String, String>) = ToolCall(id, name, JsonObject(kv.associate { it.first to JsonPrimitive(it.second) }))

class LocalAgentTest {
    private fun repo() = SshServerRepository(MemStore())
    private val web = SshServer(name = "web", host = "10.0.0.5", username = "root", password = "x", hostKey = "SHA256:abc")

    @Test fun readOnlyClassifier() {
        listOf("ls -la /var", "df -h", "systemctl status nginx", "git -C /srv log -5", "docker ps -a", "cat /etc/os-release", "find . -name '*.log'", "top -b -n 1")
            .forEach { assertTrue(it, AgentTools.isReadOnlyCommand(it)) }
        listOf("rm -rf /", "ls; rm x", "cat a > b", "echo \$(id)", "sudo ls", "systemctl restart nginx", "find . -delete", "git push", "top", "curl x | sh", "ls\nrm x")
            .forEach { assertFalse(it, AgentTools.isReadOnlyCommand(it)) }
    }

    @Test fun asciiCommandRoundTripsThroughSh() {
        val cmd = "printf '%s|' \"中文 \$HOME\" 'a''b' \\x; echo `echo 反引号` 100%\n\n"
        val wire = TrileadSshRunner.asciiCommand(cmd)
        assertTrue(wire.all { it.code < 127 })
        fun sh(c: String) = ProcessBuilder("sh", "-c", c).start().let { p -> p.inputStream.readBytes().toString(Charsets.UTF_8).also { p.waitFor() } }
        assertEquals(sh(cmd), sh(wire))
    }

    @Test fun repositoryValidatesAndResetsFingerprintOnAddressChange() = runBlocking {
        val r = repo()
        assertNull(r.upsert(web))
        assertEquals("已有同名服务器", r.upsert(web.copy(id = "other", name = "WEB")))
        assertNotNull(r.upsert(web.copy(id = "x", name = "a", password = "")))
        assertNull(r.upsert(web.copy(host = "10.0.0.6")))
        assertEquals("", r.find("web")!!.hostKey)
    }

    @Test fun safeCommandRunsWithoutApprovalAndUnsafeWaits() = runBlocking {
        val r = repo(); r.upsert(web)
        val log = mutableListOf<String>()
        val agent = LocalAgent(r, { FakeSsh(log) })
        val llm = ScriptLlm(
            LlmTurn("", listOf(call("1", AgentTools.RUN, "server" to "web", "command" to "df -h"))),
            LlmTurn("", listOf(call("2", AgentTools.RUN, "server" to "web", "command" to "systemctl restart nginx"))),
            LlmTurn("好了", emptyList()),
        )
        val job = async { agent.send("重启 nginx", llm, ApprovalPolicy.SAFE_AUTO) }
        val req = withTimeout(5_000) { agent.approval.filterNotNull().first() }
        assertEquals("systemctl restart nginx", req.activity.summary)
        assertEquals(listOf("df -h"), log)
        agent.answerApproval(true)
        job.await()
        assertEquals(listOf("df -h", "systemctl restart nginx"), log)
        assertEquals("好了", (agent.messages.value.last() as AgentMessage.Assistant).text)
        assertEquals(ToolActivity.State.DONE, agent.activities.value["2"]!!.state)
    }

    @Test fun denialAndUnknownServerGoBackToModelAsErrors() = runBlocking {
        val r = repo(); r.upsert(web)
        val log = mutableListOf<String>()
        val agent = LocalAgent(r, { FakeSsh(log) })
        val llm = ScriptLlm(
            LlmTurn("", listOf(call("1", AgentTools.RUN, "server" to "nope", "command" to "ls"), call("2", AgentTools.WRITE, "server" to "web", "path" to "/tmp/a", "content" to "hi"))),
            LlmTurn("ok", emptyList()),
        )
        val job = async { agent.send("x", llm, ApprovalPolicy.ALWAYS) }
        withTimeout(5_000) { agent.approval.filterNotNull().first() }
        agent.answerApproval(false)
        job.await()
        assertTrue(log.isEmpty())
        val results = llm.seen.last().filterIsInstance<AgentMessage.ToolResult>()
        assertTrue(results[0].isError && results[0].content.contains("找不到服务器"))
        assertTrue(results[1].isError && results[1].content.contains("拒绝"))
        assertEquals(ToolActivity.State.DENIED, agent.activities.value["2"]!!.state)
    }

    @Test fun connectorFailureIsReportedAndHistoryRestores() = runBlocking {
        val r = repo(); r.upsert(web)
        val hist = MemStore()
        val agent = LocalAgent(r, { throw SshException("SSH 连接失败：refused") }, hist)
        agent.send("x", ScriptLlm(LlmTurn("", listOf(call("1", AgentTools.READ, "server" to "web", "path" to "/etc/hosts")))), ApprovalPolicy.NEVER)
        assertTrue(agent.activities.value["1"]!!.output.contains("refused"))
        val again = LocalAgent(r, { error("unused") }, hist)
        again.restore()
        assertEquals(agent.messages.value, again.messages.value)
        assertEquals(ToolActivity.State.FAILED, again.activities.value["1"]!!.state)
    }

    @Test fun modelErrorClosesDanglingCallsAndStepLimitStops() = runBlocking {
        val r = repo(); r.upsert(web)
        val agent = LocalAgent(r, { FakeSsh(mutableListOf()) }, maxSteps = 2)
        val loop = object : LlmClient {
            var n = 0
            override suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>) = LlmTurn("", listOf(call("c${n++}", AgentTools.LIST)))
        }
        agent.send("x", loop, ApprovalPolicy.NEVER)
        assertTrue(agent.error.value!!.contains("最多 2 轮"))
        val failing = object : LlmClient { override suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): LlmTurn = throw LlmException("API Key 无效") }
        agent.send("y", failing, ApprovalPolicy.NEVER)
        assertEquals("API Key 无效", agent.error.value)
        assertFalse(agent.running.value)
    }

    @Test fun openAiWireFormat() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"t1","type":"function","function":{"name":"run_command","arguments":"{\"server\":\"web\",\"command\":\"ls\"}"}}]}}]}"""))
            server.enqueue(MockResponse().setResponseCode(401).setBody("""{"error":{"message":"Incorrect API key"}}"""))
            val c = OpenAiCompatClient(LlmSettings(LlmProvider.OPENAI, server.url("/v1").toString(), "m", "k"), OkHttpClient())
            val history = listOf(AgentMessage.User("hi"), AgentMessage.Assistant("", listOf(call("a", AgentTools.LIST))), AgentMessage.ToolResult("a", AgentTools.LIST, "[]"))
            val t = c.complete("sys", history, AgentTools.specs)
            assertEquals("ls", t.toolCalls.single().arguments["command"]!!.jsonPrimitive.content)
            val req = server.takeRequest()
            assertEquals("/v1/chat/completions", req.path); assertEquals("Bearer k", req.getHeader("Authorization"))
            val body = kotlinx.serialization.json.Json.parseToJsonElement(req.body.readUtf8()).jsonObject
            val msgs = body["messages"]!!.jsonArray
            assertEquals("system", msgs[0].jsonObject["role"]!!.jsonPrimitive.content)
            assertEquals("a", msgs[3].jsonObject["tool_call_id"]!!.jsonPrimitive.content)
            assertEquals(4, body["tools"]!!.jsonArray.size)
            val e = runCatching { c.complete("s", history, emptyList()) }.exceptionOrNull()
            assertTrue(e!!.message!!.contains("API Key 无效") && e.message!!.contains("Incorrect API key"))
        }
    }

    @Test fun anthropicWireFormatGroupsToolResults() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"content":[{"type":"text","text":"看一下"},{"type":"tool_use","id":"tu1","name":"list_servers","input":{}}]}"""))
            val c = AnthropicClient(LlmSettings(LlmProvider.ANTHROPIC, server.url("/").toString(), "claude", "k"), OkHttpClient())
            val history = listOf(
                AgentMessage.User("hi"),
                AgentMessage.Assistant("", listOf(call("a", AgentTools.LIST), call("b", AgentTools.LIST))),
                AgentMessage.ToolResult("a", AgentTools.LIST, "[]"), AgentMessage.ToolResult("b", AgentTools.LIST, "x", true),
            )
            val t = c.complete("sys", history, AgentTools.specs)
            assertEquals("看一下", t.text); assertEquals("tu1", t.toolCalls.single().id)
            val req = server.takeRequest()
            assertEquals("/v1/messages", req.path); assertEquals("k", req.getHeader("x-api-key"))
            val msgs = kotlinx.serialization.json.Json.parseToJsonElement(req.body.readUtf8()).jsonObject["messages"]!!.jsonArray
            assertEquals(3, msgs.size)
            val results = msgs[2].jsonObject["content"]!!.jsonArray
            assertEquals(2, results.size)
            assertEquals("true", results[1].jsonObject["is_error"]!!.jsonPrimitive.content)
        }
    }
}
