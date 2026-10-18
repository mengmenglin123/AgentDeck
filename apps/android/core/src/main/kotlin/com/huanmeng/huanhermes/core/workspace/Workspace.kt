package com.huanmeng.huanhermes.core.workspace

import com.huanmeng.huanhermes.core.net.HostConfig
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

data class WsEntry(val name: String, val isDir: Boolean, val size: Long?)

sealed interface WsNode {
    val path: String
    data class Dir(override val path: String, val parent: String?, val entries: List<WsEntry>) : WsNode
    data class File(override val path: String, val name: String, val size: Long?, val content: String, val binary: Boolean, val truncated: Boolean) : WsNode
}

data class GitFile(val path: String, val status: String, val staged: Boolean = false) {
    val label: String get() = when (status) {
        "M" -> "修改"; "A" -> "新增"; "D" -> "删除"; "R" -> "重命名"; "?" -> "未跟踪"; "U" -> "冲突"; "C" -> "复制"; else -> status
    }
}

data class GitStatus(val branch: String?, val files: List<GitFile>, val note: String? = null, val ahead: Int = 0) {
    val staged get() = files.filter { it.staged }
    val clean get() = files.isEmpty()
}

data class DiffLine(val kind: Kind, val text: String, val oldNo: Int? = null, val newNo: Int? = null) {
    enum class Kind { Meta, Hunk, Add, Del, Context }
}

data class FileDiff(val path: String, val lines: List<DiffLine>, val truncated: Boolean) {
    val added get() = lines.count { it.kind == DiffLine.Kind.Add }
    val removed get() = lines.count { it.kind == DiffLine.Kind.Del }
}

object Workspace {
    fun url(base: String, project: String?, path: String? = null): String {
        val q = buildList {
            if (!project.isNullOrBlank()) add("project=" + HostConfig.encode(project))
            if (!path.isNullOrBlank()) add("path=" + HostConfig.encode(path))
        }
        return if (q.isEmpty()) base else base + "?" + q.joinToString("&")
    }

    fun parseNode(data: JsonObject): WsNode {
        val path = data.s("path").orEmpty()
        return if (data.s("type") == "file") {
            WsNode.File(path, data.s("name") ?: path.substringAfterLast('/'), data.l("size"), data.s("content").orEmpty(),
                data.b("binary") == true, data.b("truncated") == true)
        } else {
            val entries = (data["entries"] as? JsonArray).orEmpty().mapNotNull { e ->
                val o = e as? JsonObject ?: return@mapNotNull null
                val name = o.s("name")?.takeIf { it.isNotBlank() && it != "." && it != ".." && !it.contains('/') } ?: return@mapNotNull null
                WsEntry(name, o.s("type") == "dir", o.l("size"))
            }.sortedWith(compareBy({ !it.isDir }, { it.name.lowercase() }))
            WsNode.Dir(path, if (path.isEmpty()) null else data.s("parent") ?: path.substringBeforeLast('/', ""), entries)
        }
    }

    fun child(dir: String, name: String) = if (dir.isEmpty()) name else "$dir/$name"

    fun parseGit(data: JsonObject) = GitStatus(
        branch = data.s("branch"),
        files = (data["files"] as? JsonArray).orEmpty().mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            GitFile(o.s("path") ?: return@mapNotNull null, o.s("status") ?: "M", o.b("staged") == true)
        },
        note = data.s("note"),
        ahead = data.l("ahead")?.toInt() ?: 0,
    )

    /** Unified diff -> numbered lines (old/new line numbers follow the hunk headers). */
    fun parseDiff(path: String, text: String, truncated: Boolean = false): FileDiff {
        val out = ArrayList<DiffLine>()
        var oldNo = 0
        var newNo = 0
        var inHunk = false
        val hunk = Regex("""^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@""")
        for (line in text.split('\n').let { if (it.lastOrNull() == "") it.dropLast(1) else it }) {
            val m = hunk.find(line)
            when {
                m != null -> {
                    oldNo = m.groupValues[1].toInt(); newNo = m.groupValues[2].toInt(); inHunk = true
                    out += DiffLine(DiffLine.Kind.Hunk, line)
                }
                !inHunk || line.startsWith("diff --git") || line.startsWith("index ") -> { inHunk = false; out += DiffLine(DiffLine.Kind.Meta, line) }
                line.startsWith("+") -> out += DiffLine(DiffLine.Kind.Add, line.drop(1), newNo = newNo++)
                line.startsWith("-") -> out += DiffLine(DiffLine.Kind.Del, line.drop(1), oldNo = oldNo++)
                line.startsWith("\\") -> out += DiffLine(DiffLine.Kind.Meta, line)
                else -> out += DiffLine(DiffLine.Kind.Context, line.removePrefix(" "), oldNo++, newNo++)
            }
        }
        return FileDiff(path, out, truncated)
    }

    fun parseDiffData(data: JsonObject, fallbackPath: String) =
        parseDiff(data.s("path") ?: fallbackPath, data.s("diff").orEmpty(), data.b("truncated") == true)

    fun languageOf(path: String): String = when (path.substringAfterLast('.', "").lowercase()) {
        "kt", "kts" -> "kotlin"; "java" -> "java"; "py" -> "python"; "js", "mjs", "cjs", "jsx" -> "javascript"
        "ts", "tsx" -> "typescript"; "go" -> "go"; "rs" -> "rust"; "sh", "bash", "zsh" -> "shell"
        "json" -> "json"; "yml", "yaml" -> "yaml"; "toml" -> "toml"; "md", "markdown" -> "markdown"
        "c", "h", "cc", "cpp", "hpp" -> "c"; "swift" -> "swift"; "dart" -> "dart"; "xml", "html" -> "xml"
        "css", "scss" -> "css"; "sql" -> "sql"
        else -> ""
    }

    fun humanSize(bytes: Long?): String = when {
        bytes == null -> ""
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> String.format(java.util.Locale.ROOT, "%.1f KB", bytes / 1024.0)
        else -> String.format(java.util.Locale.ROOT, "%.1f MB", bytes / 1024.0 / 1024.0)
    }

    private fun JsonObject.s(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.b(k: String) = (this[k] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.l(k: String) = (this[k] as? JsonPrimitive)?.longOrNull
}
