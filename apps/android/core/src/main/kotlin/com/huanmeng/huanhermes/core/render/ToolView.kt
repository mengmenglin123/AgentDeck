package com.huanmeng.huanhermes.core.render

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * What a tool call looks like in the chat, worked out from its name and raw
 * input/output (Claude Code, Codex and Hermes tool shapes). The UI only draws.
 *
 * Design borrowed from Happy's per-tool views (MIT): a shell call shows its
 * command and output, an edit shows a diff, a todo list shows checkboxes,
 * MCP tools read as "server · tool"; anything unknown falls back to pretty JSON.
 */
data class ToolView(
    val kind: Kind,
    val title: String,
    /** One line under the title: the command, path, pattern, URL… */
    val subtitle: String? = null,
    val command: String? = null,
    val path: String? = null,
    val language: String? = null,
    val diff: List<DiffLine> = emptyList(),
    /** Files a Codex `file_change` touched, with their change kind. */
    val files: List<Pair<String, String>> = emptyList(),
    val todos: List<Todo> = emptyList(),
    /** Pretty input for the generic view. */
    val input: String? = null,
    /** Readable output (Claude's `[{type:text,text}]` lists are unwrapped). */
    val output: String? = null,
) {
    enum class Kind { Shell, Edit, Write, Patch, Read, Search, Todo, Web, Agent, Mcp, Generic }

    data class Todo(val text: String, val status: String)

    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true }
        private val pretty = Json { prettyPrint = true }

        fun of(name: String, rawInput: String, rawOutput: String?): ToolView {
            val input = parse(rawInput)
            val obj = input as? JsonObject
            val output = rawOutput?.let(::readableOutput)
            fun s(vararg keys: String): String? = keys.firstNotNullOfOrNull { k -> obj?.get(k)?.text() }
            val lower = name.lowercase()

            if (name.startsWith("mcp__")) {
                val parts = name.removePrefix("mcp__").split("__", limit = 2)
                return ToolView(Kind.Mcp, parts.joinToString(" · "), input = prettyOrNull(input, rawInput), output = output)
            }
            return when (lower) {
                "bash", "command", "shell", "exec_command", "execute", "codexbash", "local_shell", "run_command", "terminal" -> {
                    val cmd = when (val c = obj?.get("command") ?: obj?.get("cmd")) {
                        is JsonArray -> c.joinToString(" ") { it.text().orEmpty() }.removePrefix("bash -lc ").trim('\'', '"')
                        null -> if (obj == null) rawInput.trim() else null
                        else -> c.text()
                    }
                    ToolView(Kind.Shell, s("description") ?: "终端命令", subtitle = cmd?.lineSequence()?.firstOrNull(), command = cmd,
                        language = "shell", output = output)
                }
                "edit", "multiedit", "search_replace", "str_replace_editor", "str_replace_based_edit_tool", "edit_file" -> {
                    val path = s("file_path", "path", "filename")
                    val edits = (obj?.get("edits") as? JsonArray)?.mapNotNull { it as? JsonObject }
                    val lines = if (edits != null) edits.flatMapIndexed { i, e ->
                        (if (i > 0) listOf(DiffLine(DiffLine.Type.Meta, "⋯")) else emptyList()) +
                            Diff.lines(e["old_string"]?.text().orEmpty(), e["new_string"]?.text().orEmpty())
                    } else Diff.lines(s("old_string", "old_str").orEmpty(), s("new_string", "new_str").orEmpty())
                    ToolView(Kind.Edit, "编辑", subtitle = path, path = path, language = Highlighter.languageForPath(path),
                        diff = lines, output = output?.takeIf { it.length < 400 })
                }
                "write", "create_file", "write_file" -> {
                    val path = s("file_path", "path", "filename")
                    val content = s("content", "file_text", "text").orEmpty()
                    ToolView(Kind.Write, "写入", subtitle = path, path = path, language = Highlighter.languageForPath(path),
                        diff = Diff.lines("", content), output = output?.takeIf { it.length < 400 })
                }
                "apply_patch", "codexpatch", "patch" -> {
                    val patch = s("patch", "input", "diff") ?: rawInput
                    ToolView(Kind.Patch, "补丁", subtitle = patchFiles(patch).joinToString(", ").ifBlank { null },
                        diff = Diff.parseUnified(patch), output = output?.takeIf { it.length < 400 })
                }
                "file_change" -> {
                    val changes = (obj?.get("changes") as? JsonArray)?.mapNotNull { c ->
                        val o = c as? JsonObject ?: return@mapNotNull null
                        val p = o["path"]?.text() ?: return@mapNotNull null
                        p to (o["kind"]?.let { k -> (k as? JsonObject)?.get("type")?.text() ?: k.text() } ?: "update")
                    }.orEmpty()
                    ToolView(Kind.Patch, "修改文件", subtitle = changes.joinToString(", ") { it.first.substringAfterLast('/') }.ifBlank { null },
                        files = changes, output = null)
                }
                "read", "read_file", "view", "cat", "notebookread" -> {
                    val path = s("file_path", "path", "notebook_path")
                    ToolView(Kind.Read, "读取", subtitle = path, path = path, language = Highlighter.languageForPath(path), output = output)
                }
                "grep", "glob", "ls", "search", "find", "list_dir", "codebase_search", "file_search" -> {
                    val pattern = s("pattern", "query", "glob", "path")
                    val where = s("path").takeIf { pattern != it }
                    ToolView(Kind.Search, name, subtitle = listOfNotNull(pattern, where?.let { "于 $it" }).joinToString(" ").ifBlank { null }, output = output)
                }
                "todowrite", "update_plan", "todo_write" -> {
                    val list = (obj?.get("todos") ?: obj?.get("plan")) as? JsonArray
                    val todos = list?.mapNotNull { t ->
                        val o = t as? JsonObject ?: return@mapNotNull null
                        val text = (o["content"] ?: o["step"] ?: o["text"])?.text() ?: return@mapNotNull null
                        Todo(text, o["status"]?.text() ?: "pending")
                    }.orEmpty()
                    ToolView(Kind.Todo, "任务清单", subtitle = "${todos.count { it.status == "completed" }}/${todos.size} 完成", todos = todos)
                }
                "webfetch", "websearch", "web_search", "fetch", "web_fetch" -> {
                    ToolView(Kind.Web, if ("search" in lower) "网页搜索" else "抓取网页", subtitle = s("url", "query", "q"), output = output)
                }
                "task", "agent", "spawn_agent", "collab_tool_call" -> {
                    ToolView(Kind.Agent, "子任务", subtitle = s("description", "prompt", "task"), input = s("prompt"), output = output)
                }
                "mcp_tool_call" -> {
                    val title = listOfNotNull(s("server"), s("tool")).joinToString(" · ").ifBlank { "MCP" }
                    ToolView(Kind.Mcp, title, input = obj?.get("arguments")?.let { prettyOrNull(it, it.toString()) }, output = output)
                }
                else -> ToolView(Kind.Generic, name, subtitle = obj?.let { firstScalar(it) } ?: rawInput.lineSequence().firstOrNull()?.take(120),
                    input = prettyOrNull(input, rawInput), output = output)
            }
        }

        private fun parse(raw: String): JsonElement? {
            val t = raw.trim()
            if (!(t.startsWith("{") || t.startsWith("["))) return null
            return runCatching { json.parseToJsonElement(t) }.getOrNull()
        }

        private fun prettyOrNull(el: JsonElement?, raw: String): String? = when (el) {
            null -> raw.ifBlank { null }
            else -> runCatching { pretty.encodeToString(JsonElement.serializer(), el) }.getOrNull() ?: raw
        }

        private fun firstScalar(o: JsonObject): String? =
            o.values.firstNotNullOfOrNull { (it as? JsonPrimitive)?.contentOrNull?.lineSequence()?.firstOrNull()?.take(120) }

        /** Claude tool results arrive as `[{"type":"text","text":…}]`; show the text. */
        fun readableOutput(raw: String): String {
            val el = parse(raw) ?: return raw
            val texts = (el as? JsonArray)?.mapNotNull { (it as? JsonObject)?.takeIf { o -> o["type"]?.text() == "text" }?.get("text")?.text() }
            if (!texts.isNullOrEmpty()) return texts.joinToString("\n")
            val o = el as? JsonObject
            o?.get("aggregated_output")?.text()?.let { return it }
            o?.get("output")?.text()?.let { return it }
            o?.get("stdout")?.text()?.let { out -> return out + (o["stderr"]?.text()?.takeIf { it.isNotBlank() }?.let { "\n$it" } ?: "") }
            return prettyOrNull(el, raw) ?: raw
        }

        private fun patchFiles(patch: String): List<String> = patch.lineSequence().mapNotNull { l ->
            when {
                l.startsWith("*** Update File: ") -> l.removePrefix("*** Update File: ")
                l.startsWith("*** Add File: ") -> l.removePrefix("*** Add File: ")
                l.startsWith("*** Delete File: ") -> l.removePrefix("*** Delete File: ")
                l.startsWith("+++ ") && !l.endsWith("/dev/null") -> l.removePrefix("+++ ").removePrefix("b/")
                else -> null
            }
        }.map { it.trim().substringAfterLast('/') }.distinct().take(6).toList()

        private fun JsonElement.text(): String? = when (this) {
            is JsonNull -> null
            is JsonPrimitive -> contentOrNull
            else -> toString()
        }
    }
}

data class DiffLine(val type: Type, val text: String) {
    enum class Type { Context, Added, Removed, Meta }
}

object Diff {
    private const val MAX_LCS = 600

    /** Line diff of [old] → [new] (LCS for small inputs, plain −/+ beyond that). */
    fun lines(old: String, new: String): List<DiffLine> {
        val a = if (old.isEmpty()) emptyList() else old.split('\n')
        val b = if (new.isEmpty()) emptyList() else new.split('\n')
        if (a.isEmpty()) return b.map { DiffLine(DiffLine.Type.Added, it) }
        if (b.isEmpty()) return a.map { DiffLine(DiffLine.Type.Removed, it) }
        if (a.size > MAX_LCS || b.size > MAX_LCS) {
            return a.map { DiffLine(DiffLine.Type.Removed, it) } + b.map { DiffLine(DiffLine.Type.Added, it) }
        }
        val dp = Array(a.size + 1) { IntArray(b.size + 1) }
        for (i in a.indices.reversed()) for (j in b.indices.reversed()) {
            dp[i][j] = if (a[i] == b[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
        }
        val out = ArrayList<DiffLine>()
        var i = 0
        var j = 0
        while (i < a.size && j < b.size) {
            when {
                a[i] == b[j] -> { out += DiffLine(DiffLine.Type.Context, a[i]); i++; j++ }
                dp[i + 1][j] >= dp[i][j + 1] -> { out += DiffLine(DiffLine.Type.Removed, a[i]); i++ }
                else -> { out += DiffLine(DiffLine.Type.Added, b[j]); j++ }
            }
        }
        while (i < a.size) out += DiffLine(DiffLine.Type.Removed, a[i++])
        while (j < b.size) out += DiffLine(DiffLine.Type.Added, b[j++])
        return out
    }

    /** Unified diff or Codex `*** Begin Patch` text into typed lines. */
    fun parseUnified(text: String): List<DiffLine> = text.split('\n').mapNotNull { l ->
        when {
            l.startsWith("*** Begin Patch") || l.startsWith("*** End Patch") -> null
            l.startsWith("***") || l.startsWith("@@") || l.startsWith("diff ") || l.startsWith("index ") ||
                l.startsWith("+++") || l.startsWith("---") -> DiffLine(DiffLine.Type.Meta, l)
            l.startsWith("+") -> DiffLine(DiffLine.Type.Added, l.substring(1))
            l.startsWith("-") -> DiffLine(DiffLine.Type.Removed, l.substring(1))
            l.startsWith(" ") -> DiffLine(DiffLine.Type.Context, l.substring(1))
            l.isEmpty() -> null
            else -> DiffLine(DiffLine.Type.Context, l)
        }
    }
}
