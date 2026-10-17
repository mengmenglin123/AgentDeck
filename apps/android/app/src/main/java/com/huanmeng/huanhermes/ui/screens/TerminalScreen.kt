package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.terminal.TerminalEmulator
import com.huanmeng.huanhermes.core.terminal.TerminalSession
import com.huanmeng.huanhermes.ui.vm.TerminalViewModel

/** xterm 16-colour palette (dark background); 16..255 are computed. */
private val ANSI = intArrayOf(
    0x1E1E1E, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xD0D0D0,
    0x5C6370, 0xFF7B86, 0xB5E890, 0xFFD68A, 0x80C4FF, 0xE09CFF, 0x7FDBE6, 0xFFFFFF,
)
private val TERM_BG = Color(0xFF0F1115)
private val TERM_FG = Color(0xFFD7DAE0)

private fun color(c: Int, fallback: Color): Color = when {
    c == TerminalEmulator.DEFAULT_COLOR -> fallback
    c and TerminalEmulator.RGB_FLAG != 0 -> Color(0xFF000000.toInt() or (c and 0xFFFFFF))
    c < 16 -> Color(0xFF000000.toInt() or ANSI[c])
    c < 232 -> {
        val i = c - 16; val steps = intArrayOf(0, 95, 135, 175, 215, 255)
        Color(steps[i / 36], steps[i / 6 % 6], steps[i % 6])
    }
    else -> { val g = 8 + (c - 232) * 10; Color(g, g, g) }
}

private fun styled(line: TerminalEmulator.Line, cursorAt: Int?): AnnotatedString = buildAnnotatedString {
    val full = if (cursorAt != null && cursorAt >= line.text.length) line.text + " ".repeat(cursorAt - line.text.length + 1) else line.text
    append(full)
    for (s in line.spans) {
        val st = s.style
        var fg = color(if (st.bold && st.fg in 0..7) st.fg + 8 else st.fg, TERM_FG)
        var bg = color(st.bg, Color.Transparent)
        if (st.inverse) { val t = fg; fg = if (bg == Color.Transparent) TERM_BG else bg; bg = t }
        addStyle(SpanStyle(
            color = if (st.dim) fg.copy(alpha = 0.6f) else fg, background = bg,
            fontWeight = if (st.bold) FontWeight.Bold else null,
            fontStyle = if (st.italic) FontStyle.Italic else null,
            textDecoration = if (st.underline) TextDecoration.Underline else null,
        ), s.start, s.end.coerceAtMost(line.text.length))
    }
    if (cursorAt != null) {
        val at = cursorAt.coerceIn(0, full.length - 1)
        val end = if (Character.isHighSurrogate(full[at])) at + 2 else at + 1
        addStyle(SpanStyle(color = TERM_BG, background = Color(0xFF8AB4F8)), at, end.coerceAtMost(full.length))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalScreen(vm: TerminalViewModel, onBack: () -> Unit) {
    val session by vm.session.collectAsStateWithLifecycle()
    val error by vm.error.collectAsStateWithLifecycle()
    val projects by vm.projects.collectAsStateWithLifecycle()
    val project by vm.project.collectAsStateWithLifecycle()
    val ctrl by vm.ctrl.collectAsStateWithLifecycle()
    val s = session
    val fallback = remember { kotlinx.coroutines.flow.MutableStateFlow(TerminalSession.Ui()) }
    val ui by (s?.ui ?: fallback).collectAsStateWithLifecycle()
    var raw by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current
    Scaffold(
        containerColor = TERM_BG,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(ui.title.ifEmpty { "终端" }, maxLines = 1)
                        val status = when (val st = ui.status) {
                            TerminalSession.Status.Opening -> "连接中…"
                            TerminalSession.Status.Open -> listOfNotNull(project ?: projects.firstOrNull()?.name, s?.read { "${it.cols}×${it.rows}" }).joinToString(" · ")
                            is TerminalSession.Status.Exited -> "已退出（${st.code ?: "?"}）"
                            is TerminalSession.Status.Failed -> st.message
                        }
                        Text(status, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = {
                    TextButton(onClick = { raw = !raw }) { Text(if (raw) "实时按键" else "整行发送") }
                    IconButton(onClick = { clipboard.getText()?.text?.let { vm.key(it) } }) { Icon(Icons.Outlined.ContentPaste, "粘贴") }
                    IconButton(onClick = { s?.restart() }) { Icon(Icons.Outlined.RestartAlt, "重新连接") }
                },
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().imePadding().testTag("terminal-screen")) {
            ProjectChips(projects, project, vm::selectProject)
            error?.let { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
            if (s != null) TerminalCanvas(s, ui.version, Modifier.weight(1f), onSize = vm::resize)
            else Box(Modifier.weight(1f))
            KeyBar(ctrl, onCtrl = { vm.ctrl.value = !vm.ctrl.value }, onKey = { vm.key(it) }, arrow = { d -> s?.arrow(d) ?: "\u001b[$d" })
            TerminalInput(enabled = ui.status == TerminalSession.Status.Open, raw = raw, onType = vm::type)
        }
    }
    ui.permission?.let { p ->
        AlertDialog(
            onDismissRequest = {},
            title = { Text("终端权限") },
            text = { Text(p.content) },
            confirmButton = {
                Row {
                    p.actions.forEach { (label, data) -> TextButton(onClick = { s?.answerPermission(data) }) { Text(label) } }
                }
            },
        )
    }
}

@Composable
private fun TerminalCanvas(s: TerminalSession, version: Long, modifier: Modifier, onSize: (Int, Int) -> Unit) {
    val style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp, lineHeight = 16.sp, color = TERM_FG)
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val cell = remember(style) { measurer.measure("MMMMMMMMMM", style).size.width / 10f }
    val lineH = with(density) { 16.sp.toPx() }
    val listState = rememberLazyListState()
    BoxWithConstraints(modifier.fillMaxWidth().background(TERM_BG).padding(horizontal = 4.dp)) {
        val cols = (constraints.maxWidth / cell).toInt().coerceIn(20, 300)
        val rows = (constraints.maxHeight / lineH).toInt().coerceIn(5, 200)
        LaunchedEffect(cols, rows) { onSize(cols, rows) }
        val snapshot = remember(version, s) {
            s.read { e ->
                val lines = e.lines()
                val cursorLine = lines.size - e.rows + e.cursorY
                Triple(lines, cursorLine, if (e.cursorVisible) e.cursorTextIndex() else null)
            }
        }
        val (lines, cursorLine, cursorIdx) = snapshot
        LaunchedEffect(lines.size, version) { if (lines.isNotEmpty()) listState.scrollToItem(lines.size - 1) }
        Box(Modifier.fillMaxSize().horizontalScroll(rememberScrollState())) {
            LazyColumn(state = listState, modifier = Modifier.fillMaxSize().testTag("terminal-lines")) {
                itemsIndexed(lines) { i, line ->
                    Text(styled(line, if (i == cursorLine) cursorIdx else null), style = style, softWrap = false, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun KeyBar(ctrl: Boolean, onCtrl: () -> Unit, onKey: (String) -> Unit, arrow: (Char) -> String) {
    val keys: List<Pair<String, () -> Unit>> = listOf(
        "Esc" to { onKey("\u001b") },
        "Tab" to { onKey("\t") },
        "Ctrl" to onCtrl,
        "^C" to { onKey("\u0003") },
        "↑" to { onKey(arrow('A')) },
        "↓" to { onKey(arrow('B')) },
        "←" to { onKey(arrow('D')) },
        "→" to { onKey(arrow('C')) },
        "|" to { onKey("|") },
        "/" to { onKey("/") },
        "-" to { onKey("-") },
        "~" to { onKey("~") },
        "Home" to { onKey("\u001b[H") },
        "End" to { onKey("\u001b[F") },
        "PgUp" to { onKey("\u001b[5~") },
        "PgDn" to { onKey("\u001b[6~") },
        "^D" to { onKey("\u0004") },
        "^Z" to { onKey("\u001a") },
    )
    Row(
        Modifier.fillMaxWidth().background(Color(0xFF181B21)).horizontalScroll(rememberScrollState()).padding(horizontal = 6.dp, vertical = 6.dp).testTag("terminal-keybar"),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        keys.forEach { (label, act) ->
            val active = label == "Ctrl" && ctrl
            Surface(
                onClick = act, shape = RoundedCornerShape(8.dp),
                color = if (active) MaterialTheme.colorScheme.primary else Color(0xFF262A33),
            ) {
                Text(label, Modifier.padding(horizontal = 12.dp, vertical = 8.dp), color = if (active) MaterialTheme.colorScheme.onPrimary else TERM_FG,
                    style = MaterialTheme.typography.labelLarge.copy(fontFamily = FontFamily.Monospace))
            }
        }
    }
}

/**
 * Keys go to the PTY as they are typed (raw mode). A one-space sentinel lets
 * backspace on an "empty" field still send DEL; IME composition (pinyin) is
 * only sent once committed.
 */
@Composable
private fun TerminalInput(enabled: Boolean, raw: Boolean, onType: (String) -> Unit) {
    val sentinel = if (raw) " " else ""
    var value by remember(raw) { mutableStateOf(TextFieldValue(sentinel, TextRange(sentinel.length))) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(enabled) { if (enabled) runCatching { focus.requestFocus() } }
    Row(Modifier.fillMaxWidth().background(Color(0xFF181B21)).navigationBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("›", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(end = 8.dp))
        BasicTextField(
            value = value,
            onValueChange = { next ->
                if (!raw || next.composition != null) { value = next; return@BasicTextField }
                val text = next.text
                when {
                    text.isEmpty() -> onType("\u007f")
                    text.length > 1 -> onType(text.drop(1).replace("\n", "\r"))
                }
                value = TextFieldValue(sentinel, TextRange(1))
            },
            enabled = enabled,
            singleLine = true,
            textStyle = TextStyle(color = TERM_FG, fontFamily = FontFamily.Monospace, fontSize = 15.sp),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, keyboardType = if (raw) KeyboardType.Ascii else KeyboardType.Text, imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = {
                if (!raw) { onType(value.text + "\r"); value = TextFieldValue("") } else onType("\r")
            }),
            modifier = Modifier.weight(1f).focusRequester(focus).testTag("terminal-input"),
            decorationBox = { inner ->
                Box {
                    if (value.text == sentinel && value.composition == null) Text(if (raw) "按键实时发送到终端" else "输入命令，回车发送", color = Color(0xFF5C6370), style = MaterialTheme.typography.bodyMedium)
                    inner()
                }
            },
        )
    }
}
