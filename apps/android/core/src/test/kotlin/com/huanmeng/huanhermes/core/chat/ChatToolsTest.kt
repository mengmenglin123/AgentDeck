package com.huanmeng.huanhermes.core.chat

import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

class ChatToolsTest {
    private val items = listOf(
        ChatItem.User(1, "修复登录"),
        ChatItem.Tool(2, "Edit", """{"file_path":"src/a.kt","old_string":"x","new_string":"y"}""", "ok"),
        ChatItem.Tool(3, "Write", """{"file_path":"src/b.kt","content":"z"}""", "ok"),
        ChatItem.Tool(4, "Edit", """{"file_path":"src/a.kt","old_string":"y","new_string":"w"}""", "ok"),
        ChatItem.Tool(5, "Bash", """{"command":"npm test"}""", "passed"),
        ChatItem.Assistant(6, "已修复 **登录**", false, null, null),
        ChatItem.RunEnded(7, "completed"),
    )

    @Test fun changedFilesGroupsByPath() {
        val files = ChangedFiles.ofTurn(items)
        assertEquals(listOf("src/a.kt", "src/b.kt"), files.map { it.path })
        assertEquals(2, files[0].edits)
        assertEquals("写入", files[1].kind)
        assertEquals(emptyList<ChangedFiles.File>(), ChangedFiles.ofTurn(items + ChatItem.User(8, "next")))
    }

    @Test fun exportAndSearch() {
        val md = TranscriptExport.markdown("登录 修复", items)
        assertTrue(md.startsWith("# 登录 修复"))
        assertTrue("## 我\n\n修复登录" in md)
        assertTrue("npm test" in md)
        assertEquals("登录-修复.md", TranscriptExport.fileName("登录 修复"))
        assertEquals(listOf(1L, 6L), TranscriptSearch.matches(items, "登录"))
        assertEquals(listOf(5L), TranscriptSearch.matches(items, "NPM"))
    }

    @Test fun quoteAndReview() {
        assertEquals("> a\n> b\n\nhi", Quote.insert("hi", "a\nb"))
        val msg = ReviewComments.message(listOf(ReviewComments.Comment("src/a.kt", 12, "val x = 1", "改成常量")))
        assertTrue("1. `src/a.kt:12`" in msg)
        assertTrue("改成常量" in msg)
    }
}

class AttachmentTest {
    @Test fun limitsAndEncoding() {
        val a = com.huanmeng.huanhermes.core.protocol.Attachment("a.png", "image/png", byteArrayOf(1, 2, 3))
        val f = com.huanmeng.huanhermes.core.protocol.Attachment("log.txt", "text/plain", "hi".toByteArray())
        assertEquals(null, com.huanmeng.huanhermes.core.protocol.Attachment.problem(listOf(a, f)))
        assertEquals("最多 4 个附件", com.huanmeng.huanhermes.core.protocol.Attachment.problem(List(5) { a }))
        val msg = com.huanmeng.huanhermes.core.protocol.Outbound.message("s", "看图", null, attachments = listOf(a, f))
        assertTrue(msg["images"].toString().contains("AQID"))
        assertTrue(msg["files"].toString().contains("log.txt"))
    }
}
