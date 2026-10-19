package com.huanmeng.huanhermes.core.agent

import com.huanmeng.huanhermes.core.ssh.SshException
import com.huanmeng.huanhermes.core.ssh.TrileadSshRunner
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/** Real sshlib + OpenAI client against server/mock-host/mock_agent_env.py (skipped without python3 + paramiko). */
class LocalAgentLiveTest {
    companion object {
        private var proc: Process? = null
        private var sshPort = 0; private var llmPort = 0; private var hostKey = ""; private var workdir = ""

        @BeforeClass @JvmStatic fun start() {
            val dir = File(System.getProperty("huanhermes.serverDir") ?: return)
            val script = File(dir, "mock-host/mock_agent_env.py").takeIf { it.exists() } ?: return
            proc = runCatching { ProcessBuilder("python3", script.absolutePath).redirectError(ProcessBuilder.Redirect.DISCARD).start() }.getOrNull() ?: return
            val line = runCatching { proc!!.inputStream.bufferedReader().readLine() }.getOrNull()
            val o = line?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() } ?: run { proc?.destroy(); proc = null; return }
            sshPort = o["ssh_port"]!!.jsonPrimitive.int; llmPort = o["llm_port"]!!.jsonPrimitive.int
            hostKey = o["host_key"]!!.jsonPrimitive.content; workdir = o["workdir"]!!.jsonPrimitive.content
        }

        @AfterClass @JvmStatic fun stop() { proc?.destroy() }
    }

    private fun server(key: String = hostKey) = SshServer(name = "mock", host = "127.0.0.1", port = sshPort, username = "hh", password = "hh-test", hostKey = key)

    @Test fun agentRunsCommandOverRealSsh() = runBlocking {
        assumeTrue(proc != null)
        val repo = SshServerRepository(MemStore()); repo.upsert(server())
        val agent = LocalAgent(repo)
        val llm = llmClientFor(LlmSettings(LlmProvider.OPENAI, "http://127.0.0.1:$llmPort/v1", "mock", "mock-key"), OkHttpClient())
        agent.send("看看服务器", llm, ApprovalPolicy.SAFE_AUTO.let { ApprovalPolicy.NEVER })
        val last = agent.messages.value.last() as AgentMessage.Assistant
        assertEquals(null, agent.error.value)
        assertTrue(last.text, last.text.contains("agent-ok") && last.text.contains("Linux"))
    }

    @Test fun readWriteRoundTripAndHostKeyEnforced() = runBlocking {
        assumeTrue(proc != null)
        val ssh = SshConnector.Trilead.open(server())
        ssh.use {
            val r = it.run("printf '中文 ok' > t.txt && cat t.txt")
            assertEquals("中文 ok", r.stdout)
        }
        assertTrue(File(workdir, "t.txt").exists())
        val bad = runCatching { SshConnector.Trilead.open(server("SHA256:wrong")) }.exceptionOrNull()
        assertTrue(bad is SshException)
        val none = runCatching { SshConnector.Trilead.open(server("")) }.exceptionOrNull()
        assertTrue(none!!.message!!.contains("测试连接"))
        // TOFU path used by the app's "test connection": the verifier sees the same fingerprint the mock printed.
        var seen = ""
        TrileadSshRunner(server().target(), { _, fp -> seen = fp; true }).close()
        assertEquals(hostKey, seen)
    }

    @Test fun badApiKeyIsReadable() = runBlocking {
        assumeTrue(proc != null)
        val repo = SshServerRepository(MemStore()); repo.upsert(server())
        val agent = LocalAgent(repo)
        agent.send("x", llmClientFor(LlmSettings(LlmProvider.OPENAI, "http://127.0.0.1:$llmPort/v1", "m", "wrong"), OkHttpClient()), ApprovalPolicy.NEVER)
        assertTrue(agent.error.value!!.contains("API Key"))
    }
}
