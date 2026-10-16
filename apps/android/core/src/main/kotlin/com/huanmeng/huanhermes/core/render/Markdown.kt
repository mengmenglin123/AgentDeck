package com.huanmeng.huanhermes.core.render

import org.commonmark.ext.autolink.AutolinkExtension
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TableRow
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.ext.task.list.items.TaskListItemMarker
import org.commonmark.ext.task.list.items.TaskListItemsExtension
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.Code
import org.commonmark.node.Emphasis
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HardLineBreak
import org.commonmark.node.Heading
import org.commonmark.node.HtmlBlock
import org.commonmark.node.HtmlInline
import org.commonmark.node.Image
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text
import org.commonmark.node.ThematicBreak
import org.commonmark.parser.Parser

/**
 * Chat Markdown, parsed into a small immutable block model the UI draws.
 *
 * CommonMark + GFM (tables, strikethrough, task lists, bare-URL autolinks).
 * Pure JVM so it runs off the main thread and is unit-tested; equal blocks
 * compare equal, so while a reply streams only the blocks that changed recompose.
 * Single newlines inside a paragraph stay line breaks (chat convention).
 */
object Markdown {
    private val parser: Parser = Parser.builder()
        .extensions(
            listOf(
                TablesExtension.create(),
                StrikethroughExtension.create(),
                TaskListItemsExtension.create(),
                AutolinkExtension.create(),
            ),
        )
        .build()

    private const val CJK_TRAILING = "。，、；：！？）】」』》…"

    /** Beyond this the reply is shown as one plain paragraph (keeps the UI responsive). */
    const val MAX_CHARS = 200_000

    fun parse(source: String): List<MdBlock> {
        if (source.isBlank()) return emptyList()
        if (source.length > MAX_CHARS) return listOf(MdBlock.Paragraph(MdText(source, emptyList())))
        val doc = parser.parse(source)
        return blocks(doc)
    }

    private fun blocks(parent: Node): List<MdBlock> {
        val out = ArrayList<MdBlock>()
        var n = parent.firstChild
        while (n != null) {
            block(n)?.let(out::add)
            n = n.next
        }
        return out
    }

    private fun block(n: Node): MdBlock? = when (n) {
        is Paragraph -> {
            val image = (n.firstChild as? Image)?.takeIf { it.next == null }
            if (image != null) MdBlock.Image(inlineText(image).text, image.destination ?: "")
            else MdBlock.Paragraph(inlineText(n))
        }
        is Heading -> MdBlock.Heading(n.level.coerceIn(1, 6), inlineText(n))
        is FencedCodeBlock -> MdBlock.CodeBlock(
            n.info?.trim()?.substringBefore(' ')?.ifBlank { null }?.lowercase(),
            n.literal.orEmpty().removeSuffix("\n"),
        )
        is IndentedCodeBlock -> MdBlock.CodeBlock(null, n.literal.orEmpty().removeSuffix("\n"))
        is BlockQuote -> MdBlock.Quote(blocks(n))
        is BulletList -> MdBlock.ListBlock(ordered = false, start = 1, items = items(n))
        is OrderedList -> MdBlock.ListBlock(ordered = true, start = n.markerStartNumber ?: 1, items = items(n))
        is ThematicBreak -> MdBlock.Rule
        is TableBlock -> table(n)
        is HtmlBlock -> MdBlock.Paragraph(MdText(n.literal.orEmpty().trimEnd(), emptyList()))
        else -> null
    }

    private fun items(list: Node): List<MdListItem> {
        val out = ArrayList<MdListItem>()
        var item = list.firstChild
        while (item != null) {
            if (item is ListItem) {
                val marker = (item.firstChild as? TaskListItemMarker) ?: (item.firstChild?.firstChild as? TaskListItemMarker)
                out += MdListItem(task = marker?.isChecked, blocks = blocks(item))
            }
            item = item.next
        }
        return out
    }

    private fun table(t: TableBlock): MdBlock.Table {
        val rows = ArrayList<List<MdText>>()
        var header: List<MdText> = emptyList()
        var align: List<MdAlign> = emptyList()
        fun walk(node: Node) {
            var c = node.firstChild
            while (c != null) {
                if (c is TableRow) {
                    val cells = ArrayList<MdText>()
                    val al = ArrayList<MdAlign>()
                    var isHeader = false
                    var cell = c.firstChild
                    while (cell != null) {
                        if (cell is TableCell) {
                            cells += inlineText(cell)
                            isHeader = cell.isHeader
                            al += when (cell.alignment) {
                                TableCell.Alignment.CENTER -> MdAlign.Center
                                TableCell.Alignment.RIGHT -> MdAlign.End
                                else -> MdAlign.Start
                            }
                        }
                        cell = cell.next
                    }
                    if (isHeader && header.isEmpty()) { header = cells; align = al } else rows += cells
                } else walk(c)
                c = c.next
            }
        }
        walk(t)
        val width = maxOf(header.size, rows.maxOfOrNull { it.size } ?: 0)
        fun pad(r: List<MdText>) = if (r.size >= width) r else r + List(width - r.size) { MdText.Empty }
        return MdBlock.Table(pad(header), align + List((width - align.size).coerceAtLeast(0)) { MdAlign.Start }, rows.map(::pad))
    }

    /** Flattens inline children into text plus style ranges. */
    private fun inlineText(parent: Node): MdText {
        val sb = StringBuilder()
        val spans = ArrayList<MdSpan>()
        fun styled(style: MdStyle, node: Node, body: () -> Unit) {
            val start = sb.length
            body()
            if (sb.length > start) spans += MdSpan(start, sb.length, style)
        }
        fun walk(node: Node) {
            var next = node.firstChild
            while (next != null) {
                val c: Node = next
                when (c) {
                    is Text -> sb.append(c.literal)
                    is Code -> styled(MdStyle.Code, c) { sb.append(c.literal) }
                    is Emphasis -> styled(MdStyle.Italic, c) { walk(c) }
                    is StrongEmphasis -> styled(MdStyle.Bold, c) { walk(c) }
                    is Strikethrough -> styled(MdStyle.Strike, c) { walk(c) }
                    is Link -> {
                        val start = sb.length
                        walk(c)
                        if (sb.length == start) sb.append(c.destination)
                        var url = c.destination ?: ""
                        var end = sb.length
                        // Bare URLs swallow trailing CJK punctuation ("见 https://a.b。"); give it back.
                        if (sb.substring(start, end) == url) {
                            while (end > start + 1 && sb[end - 1] in CJK_TRAILING) { end--; url = url.dropLast(1) }
                        }
                        spans += MdSpan(start, end, MdStyle.Link(url))
                    }
                    is Image -> {
                        val start = sb.length
                        walk(c)
                        if (sb.length == start) sb.append("图片")
                        spans += MdSpan(start, sb.length, MdStyle.Link(c.destination ?: ""))
                    }
                    is SoftLineBreak, is HardLineBreak -> sb.append('\n')
                    is HtmlInline -> sb.append(c.literal)
                    is TaskListItemMarker -> Unit
                    else -> walk(c)
                }
                next = c.next
            }
        }
        walk(parent)
        // A task marker leaves a leading space behind.
        var trimmed = 0
        while (trimmed < sb.length && sb[trimmed] == ' ' && parent.firstChild is TaskListItemMarker) trimmed++
        if (trimmed == 0) return MdText(sb.toString(), spans)
        return MdText(
            sb.substring(trimmed),
            spans.mapNotNull { s ->
                val a = (s.start - trimmed).coerceAtLeast(0)
                val b = s.end - trimmed
                if (b <= a) null else s.copy(start = a, end = b)
            },
        )
    }
}

sealed interface MdBlock {
    data class Paragraph(val text: MdText) : MdBlock
    data class Heading(val level: Int, val text: MdText) : MdBlock
    data class CodeBlock(val language: String?, val code: String) : MdBlock
    data class Quote(val blocks: List<MdBlock>) : MdBlock
    data class ListBlock(val ordered: Boolean, val start: Int, val items: List<MdListItem>) : MdBlock
    data class Table(val header: List<MdText>, val align: List<MdAlign>, val rows: List<List<MdText>>) : MdBlock
    data class Image(val alt: String, val url: String) : MdBlock
    data object Rule : MdBlock
}

/** [task] is null for a plain item, else whether its checkbox is ticked. */
data class MdListItem(val task: Boolean?, val blocks: List<MdBlock>)

enum class MdAlign { Start, Center, End }

data class MdText(val text: String, val spans: List<MdSpan>) {
    companion object { val Empty = MdText("", emptyList()) }
}

data class MdSpan(val start: Int, val end: Int, val style: MdStyle)

sealed interface MdStyle {
    data object Bold : MdStyle
    data object Italic : MdStyle
    data object Strike : MdStyle
    data object Code : MdStyle
    data class Link(val url: String) : MdStyle
}
