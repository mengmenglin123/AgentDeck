package com.huanmeng.huanhermes.core.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ComposerTest {
    @Test fun slashSuggestions() {
        assertTrue(SlashCommands.suggestions("hello").isEmpty())
        assertEquals(SlashCommands.BUILT_IN.size, SlashCommands.suggestions("/").size)
        assertEquals(listOf("/model", "/mode"), SlashCommands.suggestions("/mo").map { it.command })
        assertTrue(SlashCommands.suggestions("/model x").isEmpty())
        assertTrue("exact match closes the palette", SlashCommands.suggestions("/compact").isEmpty())
    }

    @Test fun foldsFinishedTurnsOnly() {
        val items = listOf(
            ChatItem.User(1, "q1"),
            ChatItem.Thinking(2, "hm"),
            ChatItem.Tool(3, "Bash", "{}", output = "ok"),
            ChatItem.Tool(4, "Edit", "{}", output = "err", isError = true),
            ChatItem.Assistant(5, "done", false, null, null),
            ChatItem.RunEnded(6, "completed"),
            ChatItem.User(7, "q2"),
            ChatItem.Tool(8, "Read", "{}", output = "x"),
            ChatItem.Tool(9, "Read", "{}"),
        )
        val rows = TurnFolding.fold(items)
        assertEquals(listOf(1L, -2L, 5L, 6L, 7L, 8L, 9L), rows.map { it.key })
        val folded = rows[1] as ChatRowModel.FoldedWork
        assertEquals(3, folded.children.size)
        assertEquals("已工作 · 2 次工具调用 · 思考 1 段 · 1 次失败", folded.summary)
    }

    @Test fun singleToolTurnStaysUnfolded() {
        val items = listOf(ChatItem.User(1, "q"), ChatItem.Tool(2, "Bash", "{}", output = "ok"), ChatItem.RunEnded(3, "completed"))
        assertTrue(TurnFolding.fold(items).all { it is ChatRowModel.Item })
    }
}
