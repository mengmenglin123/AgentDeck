package com.huanmeng.huanhermes.core.chat

import com.huanmeng.huanhermes.core.render.ToolView

/** Export a session as Markdown (for the system share sheet). Tool calls become one line each. */
object TranscriptExport {
    fun markdown(title: String, items: List<ChatItem>, host: String? = null): String = buildString {
        append("# ").append(title.ifBlank { "会话" }).append('\n')
        if (!host.isNullOrBlank()) append("\n> Host：").append(host).append('\n')
        items.forEach { item ->
            when (item) {
                is ChatItem.User -> append("\n## 我\n\n").append(item.text.trim()).append('\n')
                is ChatItem.Assistant -> if (item.text.isNotBlank()) append("\n## Agent\n\n").append(item.text.trim()).append('\n')
                is ChatItem.Tool -> {
                    val v = ToolView.of(item.name, item.input, item.output)
                    append("\n- 工具 ").append(v.title)
                    (v.subtitle ?: v.path ?: v.command)?.let { append("：`").append(it.replace("`", "'").take(200)).append('`') }
                    if (item.isError) append("（失败）")
                    append('\n')
                }
                is ChatItem.Permission -> append("\n> 权限请求：").append(item.text.lineSequence().firstOrNull().orEmpty())
                    .append(item.decision?.let { "（$it）" } ?: "").append('\n')
                is ChatItem.Failure -> append("\n> 错误：").append(item.text).append('\n')
                is ChatItem.RunEnded -> append("\n---\n")
                is ChatItem.Thinking, is ChatItem.Notice, is ChatItem.Unsupported -> Unit
            }
        }
    }

    /** A filename-safe slug for the exported file. */
    fun fileName(title: String): String =
        (title.trim().replace(Regex("[\\\\/:*?\"<>|\\s]+"), "-").trim('-').take(40).ifEmpty { "session" }) + ".md"
}

/** In-chat search over user/assistant/tool text; returns matching item ids in order. */
object TranscriptSearch {
    fun matches(items: List<ChatItem>, query: String): List<Long> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        return items.filter { textOf(it)?.contains(q, ignoreCase = true) == true }.map { it.id }
    }

    fun textOf(item: ChatItem): String? = when (item) {
        is ChatItem.User -> item.text
        is ChatItem.Assistant -> item.text
        is ChatItem.Tool -> item.name + "\n" + item.input + "\n" + item.output.orEmpty()
        is ChatItem.Permission -> item.text
        is ChatItem.Failure -> item.text
        else -> null
    }
}

/** "Reply with quote": the message as a Markdown blockquote ahead of the cursor. */
object Quote {
    fun of(text: String, maxLines: Int = 8): String {
        val lines = text.trim().lines()
        val kept = lines.take(maxLines).map { "> $it".trimEnd() }
        return (kept + if (lines.size > maxLines) listOf("> …") else emptyList()).joinToString("\n") + "\n\n"
    }

    fun insert(current: String, text: String): String = of(text) + current
}

/** Files the agent touched since the last user message (the "this turn changed" card). */
object ChangedFiles {
    data class File(val path: String, val kind: String, val edits: Int)

    fun ofTurn(items: List<ChatItem>): List<File> {
        val start = items.indexOfLast { it is ChatItem.User } + 1
        return of(items.subList(start.coerceAtMost(items.size), items.size))
    }

    fun of(items: List<ChatItem>): List<File> {
        val out = LinkedHashMap<String, File>()
        items.filterIsInstance<ChatItem.Tool>().filterNot { it.isError }.forEach { t ->
            val v = ToolView.of(t.name, t.input, t.output)
            val touched: List<Pair<String, String>> = when (v.kind) {
                ToolView.Kind.Edit -> listOfNotNull(v.path?.let { it to "修改" })
                ToolView.Kind.Write -> listOfNotNull(v.path?.let { it to "写入" })
                ToolView.Kind.Patch -> v.files.map { (p, k) -> p to label(k) }.ifEmpty { listOfNotNull(v.path?.let { it to "修改" }) }
                else -> emptyList()
            }
            touched.forEach { (p, k) ->
                val prev = out[p]
                out[p] = File(p, prev?.kind ?: k, (prev?.edits ?: 0) + 1)
            }
        }
        return out.values.toList()
    }

    private fun label(kind: String) = when (kind.lowercase()) {
        "add", "added", "create" -> "新建"
        "delete", "deleted", "remove" -> "删除"
        else -> "修改"
    }
}

/** Diff review comments sent back to the agent as one message (no git write access needed). */
object ReviewComments {
    data class Comment(val path: String, val line: Int?, val code: String, val note: String)

    fun message(comments: List<Comment>): String = buildString {
        append("请根据以下代码审查意见修改：\n")
        comments.forEachIndexed { i, c ->
            append('\n').append(i + 1).append(". `").append(c.path)
            c.line?.let { append(':').append(it) }
            append("`\n")
            if (c.code.isNotBlank()) append("   > ").append(c.code.trim().take(160)).append('\n')
            append("   ").append(c.note.trim()).append('\n')
        }
    }.trimEnd()
}
