package com.huanmeng.huanhermes.core.chat

/** Built-in slash commands offered by the composer palette (the Host interprets them). */
data class SlashCommand(val command: String, val description: String, val takesArgument: Boolean = false)

object SlashCommands {
    val BUILT_IN = listOf(
        SlashCommand("/model", "切换模型", takesArgument = true),
        SlashCommand("/mode", "切换模式（default / plan / acceptEdits）", takesArgument = true),
        SlashCommand("/status", "查看会话状态与上下文用量"),
        SlashCommand("/compact", "压缩上下文"),
        SlashCommand("/clear", "清空上下文，开始新话题"),
        SlashCommand("/cost", "查看本会话花费"),
        SlashCommand("/review", "让 Agent 审查当前改动"),
        SlashCommand("/init", "生成项目说明文件"),
        SlashCommand("/help", "列出 Host 支持的命令"),
    )

    val MODES = listOf("default", "plan", "acceptEdits")

    /** Palette entries while the input is a bare `/word` (no space yet). */
    fun suggestions(input: String, extra: List<SlashCommand> = emptyList()): List<SlashCommand> {
        if (!input.startsWith("/") || input.contains(' ') || input.contains('\n')) return emptyList()
        val q = input.lowercase()
        val all = (BUILT_IN + extra).distinctBy { it.command }
        return all.filter { it.command.lowercase().startsWith(q) && it.command.lowercase() != q }
            .ifEmpty { if (q == "/") all else emptyList() }
    }

    fun modelCommand(model: String) = "/model $model"
    fun modeCommand(mode: String) = "/mode $mode"
}

/** A message typed while the Agent was busy; sent in order after `run_done`. */
data class QueuedSend(val msgId: String, val text: String)

/** One row the chat list draws: a transcript item, or a finished turn's work folded into one line. */
sealed class ChatRowModel {
    abstract val key: Long

    data class Item(val item: ChatItem) : ChatRowModel() {
        override val key: Long get() = item.id
    }

    data class FoldedWork(
        val first: Long,
        val children: List<ChatItem>,
        val toolCalls: Int,
        val thinking: Int,
        val failedTools: Int,
    ) : ChatRowModel() {
        override val key: Long get() = -first
        val summary: String
            get() = buildList {
                if (toolCalls > 0) add("$toolCalls 次工具调用")
                if (thinking > 0) add("思考 $thinking 段")
                if (failedTools > 0) add("$failedTools 次失败")
            }.joinToString(" · ").let { if (it.isEmpty()) "已工作" else "已工作 · $it" }
    }
}

object TurnFolding {
    /**
     * In every finished turn (a user message … run ended), thinking and tool rows
     * fold into one [ChatRowModel.FoldedWork] line placed where the first of them
     * was. Replies, permission cards, notices and failures stay visible. The turn
     * still running is never folded, and turns with fewer than [minToFold] work
     * rows stay as they are.
     */
    fun fold(items: List<ChatItem>, minToFold: Int = 2): List<ChatRowModel> {
        val out = mutableListOf<ChatRowModel>()
        var turn = mutableListOf<ChatItem>()
        fun flush(finished: Boolean) {
            if (turn.isEmpty()) return
            val work = turn.filter { it is ChatItem.Tool || it is ChatItem.Thinking }
            if (!finished || work.size < minToFold) {
                turn.forEach { out += ChatRowModel.Item(it) }
            } else {
                var placed = false
                for (it in turn) {
                    if (it is ChatItem.Tool || it is ChatItem.Thinking) {
                        if (!placed) {
                            out += ChatRowModel.FoldedWork(
                                first = it.id,
                                children = work,
                                toolCalls = work.count { w -> w is ChatItem.Tool },
                                thinking = work.count { w -> w is ChatItem.Thinking },
                                failedTools = work.count { w -> w is ChatItem.Tool && w.isError },
                            )
                            placed = true
                        }
                    } else out += ChatRowModel.Item(it)
                }
            }
            turn = mutableListOf()
        }
        for (item in items) {
            if (item is ChatItem.User) flush(finished = true)
            turn += item
            if (item is ChatItem.RunEnded) flush(finished = true)
        }
        flush(finished = false)
        return out
    }
}
