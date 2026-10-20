package com.huanmeng.huanhermes.ui.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.core.render.DiffLine
import com.huanmeng.huanhermes.core.render.Highlighter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** GitHub-like colours, one set per light/dark surface. */
@Immutable
data class CodePalette(
    val keyword: Color, val type: Color, val str: Color, val comment: Color, val number: Color,
    val annotation: Color, val function: Color, val added: Color, val removed: Color, val meta: Color,
    val addedBg: Color, val removedBg: Color, val background: Color,
)

@Composable
fun codePalette(): CodePalette {
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val bg = MaterialTheme.colorScheme.surfaceContainerHighest
    return remember(dark, bg) {
        if (dark) CodePalette(
            keyword = Color(0xFFFF7B72), type = Color(0xFFFFA657), str = Color(0xFFA5D6FF), comment = Color(0xFF8B949E),
            number = Color(0xFF79C0FF), annotation = Color(0xFF7EE787), function = Color(0xFFD2A8FF),
            added = Color(0xFF7EE787), removed = Color(0xFFFFA198), meta = Color(0xFF79C0FF),
            addedBg = Color(0x332EA043), removedBg = Color(0x33F85149), background = bg,
        ) else CodePalette(
            keyword = Color(0xFFCF222E), type = Color(0xFF953800), str = Color(0xFF0A3069), comment = Color(0xFF6E7781),
            number = Color(0xFF0550AE), annotation = Color(0xFF116329), function = Color(0xFF8250DF),
            added = Color(0xFF116329), removed = Color(0xFF82071E), meta = Color(0xFF0550AE),
            addedBg = Color(0x3329A745), removedBg = Color(0x33D73A49), background = bg,
        )
    }
}

fun highlight(code: String, language: String?, p: CodePalette): AnnotatedString {
    val tokens = Highlighter.tokenize(code, language)
    if (tokens.isEmpty()) return AnnotatedString(code)
    return buildAnnotatedString {
        append(code)
        for (t in tokens) {
            val style = when (t.kind) {
                Highlighter.Kind.Keyword -> SpanStyle(color = p.keyword)
                Highlighter.Kind.Type -> SpanStyle(color = p.type)
                Highlighter.Kind.Str -> SpanStyle(color = p.str)
                Highlighter.Kind.Comment -> SpanStyle(color = p.comment, fontStyle = FontStyle.Italic)
                Highlighter.Kind.Number -> SpanStyle(color = p.number)
                Highlighter.Kind.Annotation -> SpanStyle(color = p.annotation)
                Highlighter.Kind.Function -> SpanStyle(color = p.function)
                Highlighter.Kind.Added -> SpanStyle(color = p.added, background = p.addedBg)
                Highlighter.Kind.Removed -> SpanStyle(color = p.removed, background = p.removedBg)
                Highlighter.Kind.Meta -> SpanStyle(color = p.meta)
            }
            addStyle(style, t.start, t.end)
        }
    }
}

/** Highlighting runs off the main thread for big blocks; plain text shows until it lands. */
@Composable
private fun rememberHighlighted(code: String, language: String?, p: CodePalette): AnnotatedString {
    val small = code.length <= 3_000
    val first = remember { if (small) highlight(code, language, p) else AnnotatedString(code) }
    val value by produceState(first, code, language, p) {
        value = if (small) highlight(code, language, p) else withContext(Dispatchers.Default) { highlight(code, language, p) }
    }
    return if (value.text == code) value else AnnotatedString(code)
}

fun copyToClipboard(context: Context, text: String, label: String = "AgentDeck") {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText(label, text))
    // Android 13+ shows its own confirmation.
    if (android.os.Build.VERSION.SDK_INT < 33) Toast.makeText(context, "已复制", Toast.LENGTH_SHORT).show()
}

/**
 * Code block card: language, copy button, sideways scroll, syntax colours,
 * long blocks folded to [foldLines] lines until expanded.
 */
@Composable
fun CodeBlockView(code: String, language: String?, modifier: Modifier = Modifier, title: String? = null, foldLines: Int = 24) {
    val p = codePalette()
    val ctx = LocalContext.current
    val lines = remember(code) { code.count { it == '\n' } + 1 }
    var expanded by rememberSaveable(code.hashCode()) { mutableStateOf(false) }
    val shown = if (expanded || lines <= foldLines) code else remember(code, foldLines) { code.lineSequence().take(foldLines).joinToString("\n") }
    Surface(color = p.background, shape = RoundedCornerShape(10.dp), modifier = modifier.fillMaxWidth()) {
        Column {
            Row(Modifier.fillMaxWidth().padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    title ?: language ?: "代码", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { copyToClipboard(ctx, code) }, modifier = Modifier.size(36.dp)) {
                    Icon(Icons.Outlined.ContentCopy, "复制代码", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            val prefs = LocalChatPrefs.current
            val highlighted = rememberHighlighted(shown, language, p)
            Row(Modifier.padding(bottom = 10.dp)) {
                if (prefs.codeLineNumbers) {
                    val shownLines = shown.count { it == '\n' } + 1
                    val w = shownLines.toString().length
                    Text(
                        remember(shownLines) { (1..shownLines).joinToString("\n") { it.toString().padStart(w) } },
                        fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline, softWrap = false,
                        modifier = Modifier.padding(start = 10.dp),
                    )
                }
                Text(
                    highlighted,
                    fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
                    softWrap = prefs.codeWrap,
                    modifier = (if (prefs.codeWrap) Modifier else Modifier.horizontalScroll(rememberScrollState()))
                        .padding(start = if (prefs.codeLineNumbers) 8.dp else 12.dp, end = 12.dp),
                )
            }
            if (lines > foldLines) {
                TextButton(onClick = { expanded = !expanded }, modifier = Modifier.padding(start = 4.dp)) {
                    Text(if (expanded) "收起" else "展开全部 $lines 行")
                }
            }
        }
    }
}

/** Diff with +/− gutters and tinted rows; content lines get the file's syntax colours. */
@Composable
fun DiffView(lines: List<DiffLine>, language: String?, modifier: Modifier = Modifier, foldLines: Int = 40) {
    val p = codePalette()
    var expanded by rememberSaveable(lines.hashCode()) { mutableStateOf(false) }
    val shown = if (expanded || lines.size <= foldLines) lines else lines.take(foldLines)
    val added = lines.count { it.type == DiffLine.Type.Added }
    val removed = lines.count { it.type == DiffLine.Type.Removed }
    Surface(color = p.background, shape = RoundedCornerShape(10.dp), modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 6.dp)) {
            Text(
                buildAnnotatedString {
                    pushStyle(SpanStyle(color = p.added)); append("+$added"); pop()
                    append("  ")
                    pushStyle(SpanStyle(color = p.removed)); append("−$removed"); pop()
                },
                style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
            )
            Column(Modifier.horizontalScroll(rememberScrollState())) {
                shown.forEach { l ->
                    val (bg, sign, signColor) = when (l.type) {
                        DiffLine.Type.Added -> Triple(p.addedBg, "+", p.added)
                        DiffLine.Type.Removed -> Triple(p.removedBg, "−", p.removed)
                        DiffLine.Type.Meta -> Triple(Color.Transparent, " ", p.meta)
                        DiffLine.Type.Context -> Triple(Color.Transparent, " ", p.comment)
                    }
                    Row(Modifier.background(bg).padding(horizontal = 8.dp)) {
                        Text(sign, color = signColor, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(14.dp))
                        Text(
                            if (l.type == DiffLine.Type.Meta) AnnotatedString(l.text) else remember(l.text, language, p) { highlight(l.text, language, p) },
                            color = if (l.type == DiffLine.Type.Meta) p.meta else MaterialTheme.colorScheme.onSurface,
                            fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall, softWrap = false,
                        )
                    }
                }
            }
            if (lines.size > foldLines) {
                TextButton(onClick = { expanded = !expanded }, modifier = Modifier.padding(start = 4.dp)) {
                    Text(if (expanded) "收起" else "展开全部 ${lines.size} 行")
                }
            }
        }
    }
}
