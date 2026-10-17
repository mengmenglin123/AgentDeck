package com.huanmeng.huanhermes.core.terminal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TerminalEmulatorTest {
    private fun term(c: Int = 10, r: Int = 4) = TerminalEmulator(c, r, scrollbackLimit = 50)

    @Test fun printsWrapsAndScrollsIntoHistory() {
        val t = term()
        t.feed("hello\r\nworld\r\n1234567890ab\r\nx\r\ny")
        assertEquals("1234567890\nab\nx\ny", t.screenText())
        assertEquals(2, t.scrollbackSize)
        assertEquals("hello", t.lines().first().text)
    }

    @Test fun cursorMovesAndErase() {
        val t = term()
        t.feed("abcdef\u001b[3D\u001b[K")
        assertEquals("abc", t.screenText())
        t.feed("\u001b[2;4HZ")
        assertEquals("abc\n   Z", t.screenText())
        t.feed("\u001b[2J")
        assertEquals("", t.screenText())
        t.feed("\u001b[H12345\u001b[1;2H\u001b[2P")
        assertEquals("145", t.screenText())
        t.feed("\u001b[1;2H\u001b[2@")
        assertEquals("1  45", t.screenText())
    }

    @Test fun cjkIsTwoColumnsWide() {
        val t = term(6, 2)
        t.feed("中文ab")
        assertEquals("中文ab", t.screenText())
        t.feed("c") // wraps: 4 + 2 = 6 columns used
        assertEquals("中文ab\nc", t.screenText())
        val t2 = term(5, 2)
        t2.feed("ab中文") // 文 can't fit in the last column: wraps whole
        assertEquals("ab中\n文", t2.screenText())
    }

    @Test fun sgrSpans() {
        val t = term(20, 2)
        t.feed("a\u001b[1;31mred\u001b[0m b\u001b[38;5;200mX\u001b[38;2;1;2;3mY")
        val line = t.lines().last { it.text.isNotEmpty() }
        val red = line.spans.first()
        assertEquals(1 to 4, red.start to red.end)
        assertTrue(red.style.bold); assertEquals(1, red.style.fg)
        assertEquals(200, line.spans[1].style.fg)
        assertEquals(TerminalEmulator.RGB_FLAG or 0x010203, line.spans[2].style.fg)
    }

    @Test fun altScreenRestoresMainAndSkipsHistory() {
        val t = term()
        t.feed("shell$ ")
        t.feed("\u001b[?1049h\u001b[Hvim screen")
        assertTrue(t.altScreen)
        assertEquals("vim screen", t.screenText())
        t.feed("\u001b[?1049l")
        assertFalse(t.altScreen)
        assertEquals("shell$", t.screenText())
    }

    @Test fun scrollRegionAndReverseIndex() {
        val t = term(5, 4)
        t.feed("1\r\n2\r\n3\r\n4\u001b[2;3r\u001b[3;1H\n")
        assertEquals("1\n3\n\n4", t.screenText())
        assertEquals(0, t.scrollbackSize)
        t.feed("\u001b[2;1H\u001bM")
        assertEquals("1\n\n3\n4", t.screenText())
    }

    @Test fun reportsCursorAndTitle() {
        val t = term()
        var reply = ""
        t.onResponse = { reply = it }
        t.feed("ab\u001b[6n")
        assertEquals("\u001b[1;3R", reply)
        t.feed("\u001b]0;my title\u0007")
        assertEquals("my title", t.title)
        t.feed("\u001b[?1h")
        assertTrue(t.appCursorKeys)
    }

    @Test fun resizeKeepsCursorLine() {
        val t = term(10, 4)
        t.feed("a\r\nb\r\nc\r\nd")
        t.resize(6, 2)
        assertEquals("c\nd", t.screenText())
        assertEquals(1, t.cursorY)
        assertEquals(listOf("a", "b", "c", "d"), t.lines().map { it.text })
        t.resize(8, 5)
        assertEquals(8, t.cols)
    }

    @Test fun garbageNeverThrows() {
        val t = term()
        val r = java.util.Random(7)
        repeat(2000) { t.feed(String(CharArray(r.nextInt(20)) { (r.nextInt(0x80) + if (r.nextInt(10) == 0) 0x4e00 else 0).toChar() }) + "\u001b[" + r.nextInt(99) + ";" + r.nextInt(99) + "HJKm") }
        t.resize(3, 2); t.feed("\u001b[99;99r\u001b[?1049h\u001b[9999L\u001b[9999M\u001b[9999@x")
    }
}
