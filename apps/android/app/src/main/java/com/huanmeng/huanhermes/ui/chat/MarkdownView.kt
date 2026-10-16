package com.huanmeng.huanhermes.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.core.render.Markdown
import com.huanmeng.huanhermes.core.render.MdAlign
import com.huanmeng.huanhermes.core.render.MdBlock
import com.huanmeng.huanhermes.core.render.MdStyle
import com.huanmeng.huanhermes.core.render.MdText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Short replies parse inline; longer ones (and every streaming update) parse on a worker thread. */
private const val SYNC_PARSE_CHARS = 1_500

/**
 * Renders chat Markdown. Parsing happens off the main thread for long text and
 * keeps showing the previous blocks until the new parse lands, so a streaming
 * reply never flickers; equal blocks are skipped by recomposition.
 */
@Composable
fun MarkdownView(
    source: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    color: Color = MaterialTheme.colorScheme.onSurface,
) {
    val initial = remember { if (source.length <= SYNC_PARSE_CHARS) Markdown.parse(source) else emptyList() }
    val blocks by produceState(initial, source) {
        value = if (source.length <= SYNC_PARSE_CHARS) Markdown.parse(source)
        else withContext(Dispatchers.Default) { Markdown.parse(source) }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        blocks.forEach { Block(it, style, color) }
    }
}

@Composable
private fun Block(block: MdBlock, style: TextStyle, color: Color) {
    val t = MaterialTheme.typography
    when (block) {
        is MdBlock.Paragraph -> InlineText(block.text, style, color)
        is MdBlock.Heading -> InlineText(
            block.text,
            when (block.level) { 1 -> t.titleLarge; 2 -> t.titleMedium; else -> t.titleSmall }.copy(fontWeight = FontWeight.SemiBold),
            color,
        )
        is MdBlock.CodeBlock -> CodeBlockView(block.code, block.language)
        is MdBlock.Quote -> Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(3.dp).fillMaxHeight().background(MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(2.dp)))
            Column(Modifier.padding(start = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                block.blocks.forEach { Block(it, style, MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
        is MdBlock.ListBlock -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            block.items.forEachIndexed { i, item ->
                Row {
                    val marker = when {
                        item.task == true -> "☑"
                        item.task == false -> "☐"
                        block.ordered -> "${block.start + i}."
                        else -> "•"
                    }
                    Text(marker, style = style, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.widthIn(min = 22.dp).padding(end = 6.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        item.blocks.forEach { Block(it, style, if (item.task == true) MaterialTheme.colorScheme.onSurfaceVariant else color) }
                    }
                }
            }
        }
        is MdBlock.Table -> TableView(block, style.copy(fontSize = t.bodyMedium.fontSize), color)
        is MdBlock.Image -> {
            val uri = LocalUriHandler.current
            Text(
                "🖼 ${block.alt.ifBlank { "图片" }}",
                style = t.bodyMedium, color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable(enabled = block.url.startsWith("http")) { runCatching { uri.openUri(block.url) } },
            )
        }
        MdBlock.Rule -> HorizontalDivider(Modifier.padding(vertical = 4.dp))
    }
}

@Composable
private fun InlineText(text: MdText, style: TextStyle, color: Color) {
    Text(annotated(text), style = style, color = color)
}

@Composable
fun annotated(text: MdText): AnnotatedString {
    val codeBg = MaterialTheme.colorScheme.surfaceContainerHighest
    val link = TextLinkStyles(SpanStyle(color = MaterialTheme.colorScheme.primary, textDecoration = TextDecoration.Underline))
    return remember(text, codeBg, link) {
        buildAnnotatedString {
            append(text.text)
            for (s in text.spans) {
                if (s.start >= s.end || s.end > text.text.length) continue
                when (val st = s.style) {
                    MdStyle.Bold -> addStyle(SpanStyle(fontWeight = FontWeight.Bold), s.start, s.end)
                    MdStyle.Italic -> addStyle(SpanStyle(fontStyle = FontStyle.Italic), s.start, s.end)
                    MdStyle.Strike -> addStyle(SpanStyle(textDecoration = TextDecoration.LineThrough), s.start, s.end)
                    MdStyle.Code -> addStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = codeBg), s.start, s.end)
                    is MdStyle.Link -> if (st.url.startsWith("http://") || st.url.startsWith("https://") || st.url.startsWith("mailto:")) {
                        addLink(LinkAnnotation.Url(st.url, link), s.start, s.end)
                    }
                }
            }
        }
    }
}

/** GFM table: columns as wide as their widest cell (capped), scrolls sideways on a phone. */
@Composable
private fun TableView(table: MdBlock.Table, style: TextStyle, color: Color) {
    val cols = table.header.size.coerceAtLeast(1)
    val border = MaterialTheme.colorScheme.outlineVariant
    val headBg = MaterialTheme.colorScheme.surfaceContainerHigh
    Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
        Layout(
            content = {
                val rows = listOf(table.header) + table.rows
                rows.forEachIndexed { r, row ->
                    for (c in 0 until cols) {
                        val cell = row.getOrNull(c) ?: MdText.Empty
                        Box(
                            Modifier.border(0.5.dp, border).then(if (r == 0) Modifier.background(headBg) else Modifier)
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                        ) {
                            Text(
                                annotated(cell),
                                style = if (r == 0) style.copy(fontWeight = FontWeight.SemiBold) else style,
                                color = color,
                                textAlign = when (table.align.getOrNull(c)) { MdAlign.Center -> TextAlign.Center; MdAlign.End -> TextAlign.End; else -> TextAlign.Start },
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
            },
        ) { measurables, _ ->
            val cap = 260.dp.roundToPx()
            val minW = 48.dp.roundToPx()
            val rowCount = measurables.size / cols
            val widths = IntArray(cols) { c ->
                (0 until rowCount).maxOf { r -> measurables[r * cols + c].maxIntrinsicWidth(Constraints.Infinity) }.coerceIn(minW, cap)
            }
            // Row height = tallest cell at its column width, so borders line up.
            val heights = IntArray(rowCount) { r -> (0 until cols).maxOf { c -> measurables[r * cols + c].maxIntrinsicHeight(widths[c]) } }
            val placeablesFixed = measurables.mapIndexed { i, m -> m.measure(Constraints.fixed(widths[i % cols], heights[i / cols])) }
            layout(widths.sum(), heights.sum()) {
                var y = 0
                for (r in 0 until rowCount) {
                    var x = 0
                    for (c in 0 until cols) {
                        placeablesFixed[r * cols + c].place(x, y)
                        x += widths[c]
                    }
                    y += heights[r]
                }
            }
        }
    }
}
