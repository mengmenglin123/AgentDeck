package com.huanmeng.huanhermes.core.terminal

/**
 * A small VT100/xterm emulator for the Host PTY: enough for shells, git,
 * top/htop, less and vim. Pure Kotlin (JVM-tested); the Compose screen only
 * draws [lines]. Not thread-safe by itself: callers serialise access.
 */
class TerminalEmulator(cols: Int = 80, rows: Int = 24, private val scrollbackLimit: Int = 2000) {
    data class Style(
        val fg: Int = DEFAULT_COLOR,
        val bg: Int = DEFAULT_COLOR,
        val bold: Boolean = false,
        val dim: Boolean = false,
        val italic: Boolean = false,
        val underline: Boolean = false,
        val inverse: Boolean = false,
    ) {
        companion object { val DEFAULT = Style() }
    }

    /** [cp] = 0 marks the right half of a wide (CJK) character. */
    class Cell(var cp: Int = ' '.code, var style: Style = Style.DEFAULT) {
        fun copy() = Cell(cp, style)
    }

    data class Span(val start: Int, val end: Int, val style: Style)
    data class Line(val text: String, val spans: List<Span>)

    var cols = cols.coerceIn(2, 500); private set
    var rows = rows.coerceIn(2, 300); private set
    var cursorX = 0; private set
    var cursorY = 0; private set
    var cursorVisible = true; private set
    var title: String = ""; private set
    /** Bumped on every visible change; cheap change detection for the UI. */
    var version = 0L; private set
    /** Application cursor keys (DECCKM): arrows send ESC O x instead of ESC [ x. */
    var appCursorKeys = false; private set

    /** Replies the terminal owes the Host (cursor position reports etc.). */
    var onResponse: (String) -> Unit = {}

    private var screen = blank(this.rows)
    private var mainSaved: Array<Array<Cell>>? = null
    private val scrollback = ArrayDeque<Array<Cell>>()
    private var style = Style.DEFAULT
    private var top = 0
    private var bottom = this.rows - 1
    private var wrapPending = false
    private var autowrap = true
    private var originMode = false
    private var saved = SavedCursor(0, 0, Style.DEFAULT)
    private var insertMode = false

    private enum class State { Ground, Esc, Csi, Osc, OscEsc, Charset }
    private var state = State.Ground
    private val params = StringBuilder()
    private val osc = StringBuilder()
    private var highSurrogate: Char? = null

    private data class SavedCursor(val x: Int, val y: Int, val style: Style)

    val scrollbackSize: Int get() = scrollback.size
    val altScreen: Boolean get() = mainSaved != null

    fun feed(text: String) {
        for (ch in text) {
            if (ch.isHighSurrogate()) { highSurrogate = ch; continue }
            val cp = if (ch.isLowSurrogate() && highSurrogate != null) Character.toCodePoint(highSurrogate!!, ch) else ch.code
            highSurrogate = null
            step(cp)
        }
        version++
    }

    private fun step(cp: Int) {
        when (state) {
            State.Ground -> ground(cp)
            State.Esc -> esc(cp)
            State.Csi -> csi(cp)
            State.Osc -> when (cp) {
                0x07 -> { endOsc(); state = State.Ground }
                0x1b -> state = State.OscEsc
                else -> if (osc.length < 512) osc.appendCodePoint(cp)
            }
            State.OscEsc -> { endOsc(); state = if (cp == '\\'.code) State.Ground else State.Ground.also { esc(cp) } }
            State.Charset -> state = State.Ground
        }
    }

    private fun ground(cp: Int) {
        when (cp) {
            0x1b -> state = State.Esc
            0x07 -> {}
            0x08 -> { if (cursorX > 0) cursorX--; wrapPending = false }
            0x09 -> { cursorX = ((cursorX / 8) + 1) * 8; if (cursorX >= cols) cursorX = cols - 1; wrapPending = false }
            0x0a, 0x0b, 0x0c -> lineFeed()
            0x0d -> { cursorX = 0; wrapPending = false }
            0x0e, 0x0f -> {}
            0x7f -> {}
            else -> if (cp >= 0x20) put(cp)
        }
    }

    private fun put(cp: Int) {
        val w = charWidth(cp)
        if (w == 0) return // combining marks: dropped (rare in shells)
        if (wrapPending) {
            if (autowrap) { cursorX = 0; lineFeed() }
            wrapPending = false
        }
        if (w == 2 && cursorX == cols - 1) {
            screen[cursorY][cursorX] = Cell(' '.code, style)
            if (autowrap) { cursorX = 0; lineFeed() } else return
        }
        val row = screen[cursorY]
        if (insertMode) {
            for (i in cols - 1 downTo cursorX + w) row[i] = row[i - w]
        }
        // Overwriting half of a wide char clears its other half.
        if (row[cursorX].cp == 0 && cursorX > 0) row[cursorX - 1] = Cell(' '.code, row[cursorX - 1].style)
        row[cursorX] = Cell(cp, style)
        if (w == 2) row[cursorX + 1] = Cell(0, style)
        else if (cursorX + 1 < cols && row[cursorX + 1].cp == 0) row[cursorX + 1] = Cell(' '.code, row[cursorX + 1].style)
        if (cursorX + w >= cols) { cursorX = cols - 1; wrapPending = true } else cursorX += w
    }

    private fun lineFeed() {
        wrapPending = false
        if (cursorY == bottom) scrollUp(1) else if (cursorY < rows - 1) cursorY++
    }

    private fun scrollUp(n: Int, toHistory: Boolean = true) {
        repeat(n.coerceAtMost(bottom - top + 1)) {
            val gone = screen[top]
            if (toHistory && top == 0 && mainSaved == null) {
                scrollback.addLast(gone)
                while (scrollback.size > scrollbackLimit) scrollback.removeFirst()
            }
            for (y in top until bottom) screen[y] = screen[y + 1]
            screen[bottom] = blankRow()
        }
    }

    private fun scrollDown(n: Int) {
        repeat(n.coerceAtMost(bottom - top + 1)) {
            for (y in bottom downTo top + 1) screen[y] = screen[y - 1]
            screen[top] = blankRow()
        }
    }

    private fun esc(cp: Int) {
        state = State.Ground
        when (cp.toChar()) {
            '[' -> { params.setLength(0); state = State.Csi }
            ']' -> { osc.setLength(0); state = State.Osc }
            '(', ')', '*', '+' -> state = State.Charset
            '7' -> saveCursor()
            '8' -> restoreCursor()
            'D' -> lineFeed()
            'E' -> { cursorX = 0; lineFeed() }
            'M' -> { wrapPending = false; if (cursorY == top) scrollDown(1) else if (cursorY > 0) cursorY-- }
            'c' -> reset()
            '=', '>' -> {}
            else -> {}
        }
    }

    private fun csi(cp: Int) {
        if (cp in 0x30..0x3f || cp == ' '.code || cp == '!'.code || cp == '"'.code || cp == '\''.code) {
            if (params.length < 64) params.appendCodePoint(cp)
            return
        }
        state = State.Ground
        val raw = params.toString()
        val private = raw.startsWith("?")
        val gt = raw.startsWith(">")
        val body = raw.trimStart('?', '>', '=').filter { it.isDigit() || it == ';' || it == ':' }
        val p = if (body.isEmpty()) emptyList() else body.split(';').map { it.substringBefore(':').toIntOrNull() ?: 0 }
        fun a(i: Int, def: Int = 1) = p.getOrNull(i)?.takeIf { it != 0 } ?: def
        wrapPending = wrapPending && cp.toChar() == 'm'
        when (cp.toChar()) {
            'A' -> cursorY = (cursorY - a(0)).coerceAtLeast(if (cursorY >= top) top else 0)
            'B', 'e' -> cursorY = (cursorY + a(0)).coerceAtMost(if (cursorY <= bottom) bottom else rows - 1)
            'C', 'a' -> cursorX = (cursorX + a(0)).coerceAtMost(cols - 1)
            'D' -> cursorX = (cursorX - a(0)).coerceAtLeast(0)
            'E' -> { cursorX = 0; cursorY = (cursorY + a(0)).coerceAtMost(bottom) }
            'F' -> { cursorX = 0; cursorY = (cursorY - a(0)).coerceAtLeast(top) }
            'G', '`' -> cursorX = (a(0) - 1).coerceIn(0, cols - 1)
            'd' -> cursorY = (a(0) - 1 + if (originMode) top else 0).coerceIn(0, rows - 1)
            'H', 'f' -> {
                val base = if (originMode) top else 0
                cursorY = (a(0) - 1 + base).coerceIn(0, rows - 1)
                cursorX = (a(1) - 1).coerceIn(0, cols - 1)
            }
            'J' -> eraseDisplay(p.getOrNull(0) ?: 0)
            'K' -> eraseLine(p.getOrNull(0) ?: 0)
            'X' -> { val n = a(0); for (x in cursorX until (cursorX + n).coerceAtMost(cols)) screen[cursorY][x] = Cell(' '.code, style.blankStyle()) }
            'P' -> { val n = a(0).coerceAtMost(cols - cursorX); val row = screen[cursorY]; for (x in cursorX until cols) row[x] = if (x + n < cols) row[x + n] else Cell(' '.code, style.blankStyle()) }
            '@' -> { val n = a(0).coerceAtMost(cols - cursorX); val row = screen[cursorY]; for (x in cols - 1 downTo cursorX) row[x] = if (x - n >= cursorX) row[x - n] else Cell(' '.code, style.blankStyle()) }
            'L' -> if (cursorY in top..bottom) { val t = top; top = cursorY; scrollDown(a(0)); top = t }
            'M' -> if (cursorY in top..bottom) { val t = top; top = cursorY; scrollUp(a(0), toHistory = false); top = t }
            'S' -> scrollUp(a(0), toHistory = false)
            'T' -> if (!gt) scrollDown(a(0))
            'm' -> sgr(p)
            'r' -> {
                val t = (a(0) - 1).coerceIn(0, rows - 1)
                val b = (a(1, rows) - 1).coerceIn(0, rows - 1)
                if (t < b) { top = t; bottom = b }
                cursorX = 0; cursorY = if (originMode) top else 0
            }
            's' -> saveCursor()
            'u' -> restoreCursor()
            'h', 'l' -> setMode(private, p, cp.toChar() == 'h')
            'n' -> if (p.getOrNull(0) == 6) onResponse("\u001b[${cursorY + 1};${cursorX + 1}R") else if (p.getOrNull(0) == 5) onResponse("\u001b[0n")
            'c' -> if (!gt) onResponse("\u001b[?1;2c") else onResponse("\u001b[>0;0;0c")
            't' -> {}
            else -> {}
        }
    }

    private fun Style.blankStyle() = Style.DEFAULT.copy(bg = bg)

    private fun setMode(private: Boolean, p: List<Int>, on: Boolean) {
        if (!private) { if (4 in p) insertMode = on; return }
        for (m in p) when (m) {
            1 -> appCursorKeys = on
            6 -> { originMode = on; cursorX = 0; cursorY = if (on) top else 0 }
            7 -> autowrap = on
            25 -> cursorVisible = on
            47, 1047, 1049 -> setAltScreen(on, saveCursor = m == 1049)
            else -> {}
        }
    }

    private fun setAltScreen(on: Boolean, saveCursor: Boolean) {
        if (on && mainSaved == null) {
            if (saveCursor) saveCursor()
            mainSaved = screen
            screen = blank(rows)
            top = 0; bottom = rows - 1
        } else if (!on && mainSaved != null) {
            screen = mainSaved!!
            mainSaved = null
            top = 0; bottom = rows - 1
            if (saveCursor) restoreCursor()
        }
    }

    private fun sgr(p: List<Int>) {
        if (p.isEmpty()) { style = Style.DEFAULT; return }
        var i = 0
        while (i < p.size) {
            when (val c = p[i]) {
                0 -> style = Style.DEFAULT
                1 -> style = style.copy(bold = true)
                2 -> style = style.copy(dim = true)
                3 -> style = style.copy(italic = true)
                4 -> style = style.copy(underline = true)
                7 -> style = style.copy(inverse = true)
                21, 22 -> style = style.copy(bold = false, dim = false)
                23 -> style = style.copy(italic = false)
                24 -> style = style.copy(underline = false)
                27 -> style = style.copy(inverse = false)
                in 30..37 -> style = style.copy(fg = c - 30)
                39 -> style = style.copy(fg = DEFAULT_COLOR)
                in 40..47 -> style = style.copy(bg = c - 40)
                49 -> style = style.copy(bg = DEFAULT_COLOR)
                in 90..97 -> style = style.copy(fg = c - 90 + 8)
                in 100..107 -> style = style.copy(bg = c - 100 + 8)
                38, 48 -> {
                    val color = when (p.getOrNull(i + 1)) {
                        5 -> p.getOrNull(i + 2)?.coerceIn(0, 255).also { i += 2 }
                        2 -> {
                            val r = p.getOrNull(i + 2) ?: 0; val g = p.getOrNull(i + 3) ?: 0; val b = p.getOrNull(i + 4) ?: 0
                            i += 4
                            RGB_FLAG or (r.coerceIn(0, 255) shl 16) or (g.coerceIn(0, 255) shl 8) or b.coerceIn(0, 255)
                        }
                        else -> null
                    }
                    if (color != null) style = if (c == 38) style.copy(fg = color) else style.copy(bg = color)
                }
                else -> {}
            }
            i++
        }
    }

    private fun eraseDisplay(mode: Int) {
        val blank = style.blankStyle()
        when (mode) {
            0 -> { eraseLine(0); for (y in cursorY + 1 until rows) screen[y] = blankRow(blank) }
            1 -> { eraseLine(1); for (y in 0 until cursorY) screen[y] = blankRow(blank) }
            2 -> for (y in 0 until rows) screen[y] = blankRow(blank)
            3 -> scrollback.clear()
        }
    }

    private fun eraseLine(mode: Int) {
        val row = screen[cursorY]
        val range = when (mode) { 0 -> cursorX until cols; 1 -> 0..cursorX.coerceAtMost(cols - 1); else -> 0 until cols }
        val blank = style.blankStyle()
        for (x in range) row[x] = Cell(' '.code, blank)
    }

    private fun saveCursor() { saved = SavedCursor(cursorX, cursorY, style) }
    private fun restoreCursor() {
        cursorX = saved.x.coerceIn(0, cols - 1); cursorY = saved.y.coerceIn(0, rows - 1); style = saved.style; wrapPending = false
    }

    private fun endOsc() {
        val s = osc.toString()
        val sep = s.indexOf(';')
        if (sep > 0 && (s.startsWith("0;") || s.startsWith("2;"))) title = s.substring(sep + 1).take(120)
    }

    fun reset() {
        screen = blank(rows); mainSaved = null; scrollback.clear()
        style = Style.DEFAULT; top = 0; bottom = rows - 1; cursorX = 0; cursorY = 0
        wrapPending = false; autowrap = true; originMode = false; insertMode = false; cursorVisible = true; appCursorKeys = false
        state = State.Ground
        version++
    }

    /** Host `terminal_clear`: wipe screen and history. */
    fun clear() { reset() }

    fun resize(newCols: Int, newRows: Int) {
        val c = newCols.coerceIn(2, 500); val r = newRows.coerceIn(2, 300)
        if (c == cols && r == rows) return
        fun fit(src: Array<Array<Cell>>, keepBottom: Boolean): Array<Array<Cell>> {
            var lines = src.toList()
            if (r < lines.size && keepBottom) {
                // Keep the cursor line visible: push the top into history.
                val drop = (lines.size - r).coerceAtMost((cursorY + 1 - r).coerceAtLeast(0))
                if (src === screen && mainSaved == null) lines.take(drop).forEach { scrollback.addLast(it) }
                lines = lines.drop(drop)
            }
            return Array(r) { y ->
                val old = lines.getOrNull(y)
                Array(c) { x -> old?.getOrNull(x)?.copy() ?: Cell() }.also { row ->
                    if (row[c - 1].cp != 0 && c < (old?.size ?: 0) && old!![c].cp == 0) row[c - 1] = Cell(' '.code, row[c - 1].style)
                }
            }
        }
        val shift = if (r < rows) (cursorY + 1 - r).coerceAtLeast(0) else 0
        screen = fit(screen, keepBottom = true)
        mainSaved = mainSaved?.let { fit(it, keepBottom = false) }
        while (scrollback.size > scrollbackLimit) scrollback.removeFirst()
        cols = c; rows = r
        cursorY = (cursorY - shift).coerceIn(0, r - 1)
        cursorX = cursorX.coerceIn(0, c - 1)
        top = 0; bottom = r - 1; wrapPending = false
        version++
    }

    /** History then screen, each line trimmed of trailing blanks; wide-char halves skipped. */
    fun lines(includeScrollback: Boolean = true): List<Line> {
        val all = (if (includeScrollback && mainSaved == null) scrollback.toList() else emptyList()) + screen.toList()
        return all.map { row -> render(row) }
    }

    /** Plain text of the visible screen (tests, copy). */
    fun screenText(): String = screen.joinToString("\n") { render(it).text }.trimEnd('\n', ' ')

    private fun render(row: Array<Cell>): Line {
        var last = row.size - 1
        while (last >= 0 && row[last].cp == ' '.code && row[last].style.bg == DEFAULT_COLOR && !row[last].style.inverse) last--
        val sb = StringBuilder()
        val spans = ArrayList<Span>()
        var spanStart = 0
        var spanStyle: Style? = null
        for (x in 0..last) {
            val cell = row[x]
            if (cell.cp == 0) continue
            if (cell.style != spanStyle) {
                if (spanStyle != null && spanStyle != Style.DEFAULT && sb.length > spanStart) spans += Span(spanStart, sb.length, spanStyle)
                spanStart = sb.length; spanStyle = cell.style
            }
            sb.appendCodePoint(cell.cp)
        }
        if (spanStyle != null && spanStyle != Style.DEFAULT && sb.length > spanStart) spans += Span(spanStart, sb.length, spanStyle)
        return Line(sb.toString(), spans)
    }

    /** Column of the cursor inside [lines]' rendered text (wide chars count once). */
    fun cursorTextIndex(): Int {
        val row = screen[cursorY]
        var idx = 0
        for (x in 0 until cursorX.coerceAtMost(row.size)) if (row[x].cp != 0) idx += Character.charCount(row[x].cp)
        return idx
    }

    private fun blankRow(s: Style = Style.DEFAULT) = Array(cols) { Cell(' '.code, s) }
    private fun blank(n: Int) = Array(n) { blankRow() }

    companion object {
        const val DEFAULT_COLOR = -1
        const val RGB_FLAG = 0x1000000

        fun charWidth(cp: Int): Int = when {
            cp == 0x200B || cp in 0x0300..0x036F || cp in 0x200C..0x200F || cp in 0xFE00..0xFE0F -> 0
            cp in 0x1100..0x115F || cp in 0x2E80..0x303E || cp in 0x3041..0x33FF || cp in 0x3400..0x4DBF ||
                cp in 0x4E00..0x9FFF || cp in 0xA000..0xA4CF || cp in 0xAC00..0xD7A3 || cp in 0xF900..0xFAFF ||
                cp in 0xFE30..0xFE4F || cp in 0xFF00..0xFF60 || cp in 0xFFE0..0xFFE6 || cp in 0x1F300..0x1F64F ||
                cp in 0x1F900..0x1F9FF || cp in 0x20000..0x3FFFD -> 2
            else -> 1
        }
    }
}
