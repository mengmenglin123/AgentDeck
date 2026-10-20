package com.huanmeng.huanhermes.core.agent

import com.huanmeng.huanhermes.core.ssh.SshRunner
import com.huanmeng.huanhermes.core.ssh.TrileadSshRunner
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runInterruptible
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.util.Base64

/** When a tool call needs the user's tap before it runs. */
@Serializable
enum class ApprovalPolicy(val label: String, val desc: String) {
    ALWAYS("每次都问我", "任何命令和写文件都要你批准"),
    SAFE_AUTO("只读自动", "查看类命令（ls、cat、df、systemctl status…）自动执行，其余要批准"),
    NEVER("全部自动", "不再询问，Agent 直接执行（风险自负）"),
}

/** What the UI shows for one tool call. */
data class ToolActivity(
    val callId: String,
    val tool: String,
    val server: String?,
    val summary: String,
    val state: State,
    val output: String = "",
) {
    enum class State { WAITING_APPROVAL, RUNNING, DONE, FAILED, DENIED }
}

data class ApprovalRequest(val activity: ToolActivity, val answer: CompletableDeferred<Boolean>)

/** The tools the phone-side agent exposes to the model. */
object AgentTools {
    const val LIST = "list_servers"
    const val RUN = "run_command"
    const val READ = "read_file"
    const val WRITE = "write_file"

    private fun schema(props: JsonObject, required: List<String>) = buildJsonObject {
        put("type", "object"); put("properties", props)
        put("required", buildJsonArray { required.forEach { add(JsonPrimitive(it)) } })
    }

    private fun str(desc: String) = buildJsonObject { put("type", "string"); put("description", desc) }

    val specs = listOf(
        ToolSpec(LIST, "列出用户在手机上保存的 SSH 服务器（名称、地址、用户名、备注）。", schema(JsonObject(emptyMap()), emptyList())),
        ToolSpec(RUN, "在指定 SSH 服务器上用 sh -c 执行一条非交互式 shell 命令，返回退出码、stdout、stderr（各最多 8000 字符）。不要运行需要交互或常驻前台的命令；需要 root 时用 sudo -n。",
            schema(buildJsonObject {
                put("server", str("服务器名称，来自 list_servers"))
                put("command", str("要执行的 shell 命令"))
                putJsonObject("timeout_seconds") { put("type", "integer"); put("description", "超时秒数，默认 60，最大 600") }
            }, listOf("server", "command"))),
        ToolSpec(READ, "读取服务器上的文本文件（默认最多 64KB）。",
            schema(buildJsonObject { put("server", str("服务器名称")); put("path", str("文件绝对路径或相对 home 的路径")) }, listOf("server", "path"))),
        ToolSpec(WRITE, "把完整内容写入服务器上的文件（覆盖；最大 256KB，会自动创建父目录）。",
            schema(buildJsonObject { put("server", str("服务器名称")); put("path", str("文件路径")); put("content", str("文件的完整新内容")) }, listOf("server", "path", "content"))),
    )

    private val safeHeads = setOf(
        "ls", "ll", "cat", "head", "tail", "wc", "stat", "file", "pwd", "whoami", "id", "hostname", "uname", "uptime", "date",
        "df", "du", "free", "ps", "pgrep", "lscpu", "lsblk", "nproc", "which", "type", "echo", "env", "printenv", "ip", "ss",
        "netstat", "grep", "egrep", "rg", "find", "tree", "realpath", "readlink", "basename", "dirname", "sha256sum", "md5sum",
        "journalctl", "dmesg", "last", "w", "who", "top", "vmstat", "iostat", "lsof", "sort", "uniq", "nvidia-smi",
    )
    private val safeSub = mapOf(
        "systemctl" to setOf("status", "is-active", "is-enabled", "list-units", "list-timers", "show", "cat"),
        "git" to setOf("status", "log", "diff", "show", "branch", "remote", "rev-parse", "describe"),
        "docker" to setOf("ps", "images", "logs", "inspect", "stats", "version", "info"),
        "kubectl" to setOf("get", "describe", "logs", "version", "top"),
        "apt" to setOf("list", "show", "policy"),
        "pip" to setOf("list", "show"),
    )
    private val unsafeChars = Regex("[;&|<>`$\\n\\r(){}]")
    private val findUnsafe = Regex("(^|\\s)-(delete|exec|execdir|ok|okdir|fprint|fprintf|fls)(\\s|$)")

    /** Conservative: a single command, no redirection or substitution, from a read-only allowlist. */
    fun isReadOnlyCommand(command: String): Boolean {
        val c = command.trim()
        if (c.isEmpty() || unsafeChars.containsMatchIn(c)) return false
        val words = c.split(Regex("\\s+"))
        var i = 0
        if (words[0] == "sudo") return false
        val head = words[0].substringAfterLast('/')
        if (head == "find" && findUnsafe.containsMatchIn(c)) return false
        if (head == "top" && !words.contains("-b")) return false
        if (head in safeHeads) return true
        val subs = safeSub[head] ?: return false
        i++
        val valued = setOf("-C", "-c", "-H", "-n", "--namespace", "--context", "-u", "--user")
        while (i < words.size && words[i].startsWith("-")) i += if (words[i] in valued) 2 else 1
        return i < words.size && words[i] in subs
    }

    fun needsApproval(policy: ApprovalPolicy, name: String, args: JsonObject): Boolean = when (policy) {
        ApprovalPolicy.NEVER -> false
        ApprovalPolicy.ALWAYS -> name != LIST
        ApprovalPolicy.SAFE_AUTO -> when (name) {
            LIST, READ -> false
            RUN -> !isReadOnlyCommand(args.s("command"))
            else -> true
        }
    }

    internal fun JsonObject.s(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull.orEmpty()
}

private fun clip(s: String, max: Int) = if (s.length <= max) s else s.take(max) + "\n…（已截断，共 ${s.length} 字符）"

/**
 * The phone-side agent loop: user text → model → tool calls on saved SSH
 * servers (each gated by [ApprovalPolicy]) → results back to the model, until
 * it answers in plain text or [maxSteps] model calls are spent. One run at a time.
 */
class LocalAgent(
    private val servers: SshServerRepository,
    private val connector: SshConnector = SshConnector.Trilead,
    val conversations: ConversationRepository? = null,
    private val maxSteps: Int = 16,
    /** Phone-side tools (web, JS, clock); read each run so settings toggles apply. */
    private val phoneTools: () -> List<PhoneTool> = { emptyList() },
) {
    /** Built-in skill pack added to the system prompt, or null. */
    @Volatile var skill: SkillPack? = null
    private var activeTools: List<PhoneTool> = emptyList()

    private val _messages = MutableStateFlow<List<AgentMessage>>(emptyList())
    val messages: StateFlow<List<AgentMessage>> = _messages
    private val _activities = MutableStateFlow<Map<String, ToolActivity>>(emptyMap())
    val activities: StateFlow<Map<String, ToolActivity>> = _activities
    private val _approval = MutableStateFlow<ApprovalRequest?>(null)
    val approval: StateFlow<ApprovalRequest?> = _approval
    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val _conversationId = MutableStateFlow<String?>(null)
    /** Null until the first message of a new conversation is sent. */
    val conversationId: StateFlow<String?> = _conversationId
    private val _streaming = MutableStateFlow<String?>(null)
    /** Assistant text arriving for the model call in flight, or null. */
    val streaming: StateFlow<String?> = _streaming

    /** Opens the newest conversation (app start). */
    suspend fun restore() {
        val repo = conversations ?: return
        repo.load().firstOrNull()?.let { open(it.id) }
    }

    /** Switches to a saved conversation; ignored while a run is going. */
    suspend fun open(id: String): Boolean {
        if (_running.value) return false
        val repo = conversations ?: return false
        val list = repo.messages(id)
        _conversationId.value = id
        _messages.value = list; _error.value = null
        rebuildActivities(list)
        return true
    }

    /** Starts an empty conversation (saved once it has a message). */
    fun newConversation(): Boolean {
        if (_running.value) return false
        _conversationId.value = null
        _messages.value = emptyList(); _activities.value = emptyMap(); _error.value = null
        return true
    }

    suspend fun deleteConversation(id: String) {
        if (_running.value && id == _conversationId.value) return
        conversations?.delete(id)
        if (id == _conversationId.value) newConversation()
    }

    private fun rebuildActivities(list: List<AgentMessage>) {
        val calls = list.filterIsInstance<AgentMessage.Assistant>().flatMap { it.toolCalls }.associateBy { it.id }
        _activities.value = list.filterIsInstance<AgentMessage.ToolResult>().associate { r ->
            val c = calls[r.callId]
            r.callId to ToolActivity(r.callId, r.name, c?.arguments?.let { a -> with(AgentTools) { a.s("server") } }?.ifEmpty { null },
                c?.let { summarize(it) } ?: r.name, if (r.isError) ToolActivity.State.FAILED else ToolActivity.State.DONE, r.content)
        }
    }

    /** Same as [newConversation]; kept for callers that "clear" the screen. */
    suspend fun clear() { newConversation() }

    fun answerApproval(ok: Boolean) { _approval.value?.answer?.complete(ok) }

    fun systemPrompt(list: List<SshServer>, tools: List<PhoneTool> = activeTools): String = buildString {
        appendLine("你是 AgentDeck 手机里的本地 Agent：可以通过 SSH 管理用户保存的服务器，也可以用手机上的工具完成通用任务。")
        appendLine("用中文回答，简洁直接，善用 Markdown。需要事实、最新信息或精确计算时调用工具，不要凭空编造。")
        if (tools.isNotEmpty()) appendLine("手机工具：" + tools.joinToString("、") { it.spec.name } + "。")
        appendLine("SSH：先用只读命令了解情况再动手；修改配置前先备份；危险或不可逆的操作（删除数据、重启、停服务、改防火墙）先说明影响。")
        appendLine("命令必须是非交互式的（不要 vim、less、top 不带 -b、tail -f）；长输出用 head/tail 截取；需要 root 用 sudo -n。")
        appendLine("用户可能拒绝某次工具调用，这时换个办法或询问用户。完成后用几句话总结做了什么和结果。")
        skill?.let { appendLine(it.prompt) }
        if (list.isEmpty()) appendLine("用户还没有保存 SSH 服务器；需要操作服务器时提示他先在「服务器」页添加，其它任务照常完成。")
        else {
            appendLine("可用服务器：")
            list.forEach { appendLine("- ${it.name}（${it.label()}）" + it.note.takeIf { n -> n.isNotBlank() }?.let { n -> "：$n" }.orEmpty()) }
        }
    }

    /** Sends [text] and runs the loop to completion. Cancel the calling coroutine to stop. */
    suspend fun send(text: String, client: LlmClient, policy: ApprovalPolicy, attachments: List<AgentAttachment> = emptyList()) {
        if (_running.value || (text.isBlank() && attachments.isEmpty())) return
        _running.value = true; _error.value = null
        val sessions = mutableMapOf<String, SshRunner>()
        activeTools = phoneTools()
        try {
            append(AgentMessage.User(text.trim(), attachments))
            val list = servers.load()
            var steps = 0
            while (true) {
                if (steps++ >= maxSteps) { _error.value = "已达到单次最多 $maxSteps 轮，先停下了。可以回复「继续」。"; break }
                _streaming.value = ""
                val turn = try {
                    client.stream(systemPrompt(list), contextWindow(), AgentTools.specs + activeTools.map { it.spec }) { delta -> _streaming.value = (_streaming.value ?: "") + delta }
                } finally { _streaming.value = null }
                append(AgentMessage.Assistant(turn.text, turn.toolCalls))
                if (turn.toolCalls.isEmpty()) break
                for (call in turn.toolCalls) append(execute(call, policy, sessions))
            }
        } catch (e: CancellationException) {
            closeDangling("已停止")
            throw e
        } catch (e: Exception) {
            closeDangling("出错，未执行")
            _error.value = e.message ?: e.javaClass.simpleName
        } finally {
            _approval.value?.answer?.complete(false); _approval.value = null
            sessions.values.forEach { runCatching { it.close() } }
            _running.value = false
            persist()
        }
    }

    /** Every tool_call needs a result or the next request is rejected: fill the gaps. */
    private fun closeDangling(reason: String) {
        val msgs = _messages.value
        val answered = msgs.filterIsInstance<AgentMessage.ToolResult>().map { it.callId }.toSet()
        val missing = msgs.filterIsInstance<AgentMessage.Assistant>().flatMap { it.toolCalls }.filter { it.id !in answered }
        if (missing.isEmpty()) return
        _messages.value = msgs + missing.map { AgentMessage.ToolResult(it.id, it.name, reason, isError = true) }
        _activities.value = _activities.value + missing.associate { c ->
            c.id to (_activities.value[c.id]?.copy(state = ToolActivity.State.FAILED, output = reason)
                ?: ToolActivity(c.id, c.name, null, summarize(c), ToolActivity.State.FAILED, reason))
        }
    }

    /** Last ~60 messages, never starting on an orphaned tool result. */
    private fun contextWindow(): List<AgentMessage> {
        val all = _messages.value
        if (all.size <= 60) return all
        var start = all.size - 60
        while (start < all.size && all[start] !is AgentMessage.User) start++
        return if (start >= all.size) all.takeLast(60).dropWhile { it is AgentMessage.ToolResult } else all.subList(start, all.size)
    }

    private suspend fun append(m: AgentMessage) { _messages.value = _messages.value + m; persist() }

    private suspend fun persist() {
        val repo = conversations ?: return
        if (_messages.value.isEmpty()) return
        val id = _conversationId.value ?: repo.newId().also { _conversationId.value = it }
        repo.save(id, _messages.value)
    }

    private fun setActivity(a: ToolActivity) { _activities.value = _activities.value + (a.callId to a) }

    fun summarize(call: ToolCall): String = with(AgentTools) {
        val a = call.arguments
        when (call.name) {
            LIST -> "列出服务器"
            RUN -> a.s("command")
            READ -> "读取 " + a.s("path")
            WRITE -> "写入 " + a.s("path") + "（${a.s("content").length} 字符）"
            else -> (activeTools + phoneTools()).firstOrNull { it.spec.name == call.name }?.summarize(a) ?: call.name
        }
    }

    private suspend fun runPhoneTool(call: ToolCall, tool: PhoneTool, policy: ApprovalPolicy): AgentMessage.ToolResult {
        val act = ToolActivity(call.id, call.name, null, tool.summarize(call.arguments), ToolActivity.State.RUNNING)
        val ask = when (policy) { ApprovalPolicy.NEVER -> false; ApprovalPolicy.ALWAYS -> true; ApprovalPolicy.SAFE_AUTO -> !tool.readOnly }
        if (ask) {
            val waiting = act.copy(state = ToolActivity.State.WAITING_APPROVAL)
            setActivity(waiting)
            val answer = CompletableDeferred<Boolean>()
            _approval.value = ApprovalRequest(waiting, answer)
            val ok = try { answer.await() } finally { _approval.value = null }
            if (!ok) {
                setActivity(act.copy(state = ToolActivity.State.DENIED, output = "用户拒绝"))
                return AgentMessage.ToolResult(call.id, call.name, "用户拒绝执行这次操作。", true)
            }
        }
        setActivity(act)
        val (text, err) = try { tool.run(call.arguments) } catch (e: CancellationException) { throw e } catch (e: Exception) { (e.message ?: e.javaClass.simpleName) to true }
        setActivity(act.copy(state = if (err) ToolActivity.State.FAILED else ToolActivity.State.DONE, output = text))
        return AgentMessage.ToolResult(call.id, call.name, text, err)
    }

    private suspend fun execute(call: ToolCall, policy: ApprovalPolicy, sessions: MutableMap<String, SshRunner>): AgentMessage.ToolResult = with(AgentTools) {
        val a = call.arguments
        val serverName = a.s("server").ifEmpty { null }
        val base = ToolActivity(call.id, call.name, serverName, summarize(call), ToolActivity.State.RUNNING)
        fun fail(msg: String): AgentMessage.ToolResult { setActivity(base.copy(state = ToolActivity.State.FAILED, output = msg)); return AgentMessage.ToolResult(call.id, call.name, msg, true) }

        activeTools.firstOrNull { it.spec.name == call.name }?.let { tool -> return runPhoneTool(call, tool, policy) }
        if (call.name !in setOf(LIST, RUN, READ, WRITE)) return fail("未知工具：${call.name}")
        if (call.name == LIST) {
            val out = buildJsonArray {
                servers.servers.value.forEach { s -> add(buildJsonObject { put("name", s.name); put("address", s.label()); put("note", s.note); put("host_key_confirmed", s.hostKey.isNotBlank()) }) }
            }.toString()
            setActivity(base.copy(state = ToolActivity.State.DONE, output = out))
            return AgentMessage.ToolResult(call.id, call.name, out)
        }
        val server = serverName?.let { servers.find(it) } ?: return fail("找不到服务器「${serverName.orEmpty()}」。可用：" + servers.servers.value.joinToString("、") { it.name }.ifEmpty { "（无）" })
        when (call.name) {
            RUN -> if (a.s("command").isBlank()) return fail("command 不能为空")
            READ -> if (a.s("path").isBlank()) return fail("path 不能为空")
            WRITE -> { if (a.s("path").isBlank()) return fail("path 不能为空"); if (a.s("content").length > 256 * 1024) return fail("内容超过 256KB") }
        }
        val act = base.copy(server = server.name)
        if (needsApproval(policy, call.name, a)) {
            val waiting = act.copy(state = ToolActivity.State.WAITING_APPROVAL)
            setActivity(waiting)
            val answer = CompletableDeferred<Boolean>()
            _approval.value = ApprovalRequest(waiting, answer)
            val ok = try { answer.await() } finally { _approval.value = null }
            if (!ok) {
                setActivity(act.copy(state = ToolActivity.State.DENIED, output = "用户拒绝"))
                return AgentMessage.ToolResult(call.id, call.name, "用户拒绝执行这次操作。", true)
            }
        }
        setActivity(act)
        return try {
            val ssh = sessions[server.id] ?: runInterruptible(Dispatchers.IO) { connector.open(server) }.also { sessions[server.id] = it }
            val text = runInterruptible(Dispatchers.IO) {
                when (call.name) {
                    RUN -> {
                        val timeout = ((a["timeout_seconds"] as? JsonPrimitive)?.intOrNull ?: 60).coerceIn(1, 600)
                        val r = ssh.run(a.s("command"), timeout * 1000L)
                        buildString {
                            append("exit_code: ${r.exitCode ?: "unknown"}\n")
                            if (r.stdout.isNotEmpty()) append("stdout:\n").append(clip(r.stdout, 8000)).append('\n')
                            if (r.stderr.isNotEmpty()) append("stderr:\n").append(clip(r.stderr, 8000)).append('\n')
                            if (r.stdout.isEmpty() && r.stderr.isEmpty()) append("（无输出）")
                        }.trimEnd() to (r.exitCode != 0)
                    }
                    READ -> {
                        val q = TrileadSshRunner.shellQuote(a.s("path"))
                        val r = ssh.run("f=$q; [ -f \"\$f\" ] || { echo \"不是文件或不存在: \$f\" >&2; exit 2; }; head -c 65536 -- \"\$f\"; s=\$(wc -c < \"\$f\"); [ \"\$s\" -gt 65536 ] && printf '\\n…（文件共 %s 字节，只显示前 64KB）' \"\$s\"; true", 60_000)
                        if (r.exitCode != 0) (r.stderr.ifBlank { "读取失败（退出码 ${r.exitCode}）" }).trim() to true else r.stdout to false
                    }
                    else -> {
                        val q = TrileadSshRunner.shellQuote(a.s("path"))
                        val b64 = Base64.getEncoder().encodeToString(a.s("content").toByteArray(Charsets.UTF_8))
                        val r = ssh.run("f=$q; d=\$(dirname -- \"\$f\"); mkdir -p -- \"\$d\" && printf '%s' '$b64' | base64 -d > \"\$f\" && wc -c < \"\$f\"", 120_000)
                        if (r.exitCode != 0) (r.stderr.ifBlank { "写入失败（退出码 ${r.exitCode}）" }).trim() to true else "已写入 ${r.stdout.trim()} 字节" to false
                    }
                }
            }
            setActivity(act.copy(state = if (text.second) ToolActivity.State.FAILED else ToolActivity.State.DONE, output = text.first))
            AgentMessage.ToolResult(call.id, call.name, text.first, text.second)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            sessions.remove(server.id)?.let { runCatching { it.close() } }
            fail(e.message ?: e.javaClass.simpleName)
        }
    }
}
