package com.huanmeng.huanhermes.core.agent

import org.jsoup.Jsoup
import org.jsoup.parser.Parser
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/**
 * Turns an attached file into text the model can read. Office Open XML
 * (docx/xlsx/pptx), OpenDocument, HTML, and plain text/code are handled here;
 * PDF needs a platform reader and is passed in as [pdf].
 */
object DocumentText {
    const val MAX_CHARS = 60_000

    private val textExt = setOf(
        "txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "xml", "yaml", "yml", "toml", "ini", "conf", "cfg", "log", "properties",
        "kt", "kts", "java", "py", "js", "ts", "tsx", "jsx", "go", "rs", "c", "h", "cpp", "hpp", "cs", "swift", "rb", "php", "sh", "bash",
        "zsh", "sql", "gradle", "dart", "lua", "r", "m", "scala", "vue", "svelte", "css", "scss", "less", "env", "gitignore", "dockerfile", "tex", "srt",
    )

    fun ext(name: String) = name.substringAfterLast('.', "").lowercase().ifEmpty { name.lowercase() }

    fun isImage(name: String, mime: String) = mime.startsWith("image/") || ext(name) in setOf("png", "jpg", "jpeg", "webp", "gif", "heic", "bmp")

    /** Null when the type is unknown and the bytes do not look like text. */
    fun extract(name: String, mime: String, bytes: ByteArray, pdf: ((ByteArray) -> String)? = null): String? {
        val e = ext(name)
        val raw = when {
            e == "pdf" || mime == "application/pdf" -> pdf?.invoke(bytes) ?: return null
            e == "docx" || mime.contains("wordprocessingml") -> docx(bytes)
            e == "xlsx" || mime.contains("spreadsheetml") -> xlsx(bytes)
            e == "pptx" || mime.contains("presentationml") -> pptx(bytes)
            e in setOf("odt", "ods", "odp") || mime.contains("opendocument") -> odf(bytes)
            e in setOf("html", "htm") || mime.contains("html") -> WebFetchTool.htmlToText(bytes.toString(Charsets.UTF_8))
            e in textExt || mime.startsWith("text/") || mime.contains("json") || mime.contains("xml") -> decodeText(bytes)
            looksLikeText(bytes) -> decodeText(bytes)
            else -> return null
        }
        val t = raw.replace(Regex("[ \\t]+\\n"), "\n").replace(Regex("\\n{3,}"), "\n\n").trim()
        return if (t.length <= MAX_CHARS) t else t.take(MAX_CHARS) + "\n…（文档较长，只保留前 $MAX_CHARS 字符，共 ${t.length} 字符）"
    }

    private fun decodeText(b: ByteArray): String {
        if (b.size >= 2 && b[0] == 0xFF.toByte() && b[1] == 0xFE.toByte()) return String(b, Charsets.UTF_16LE).drop(1)
        if (b.size >= 2 && b[0] == 0xFE.toByte() && b[1] == 0xFF.toByte()) return String(b, Charsets.UTF_16BE).drop(1)
        val s = String(b, Charsets.UTF_8)
        if (s.count { it == '\uFFFD' } > s.length / 50) runCatching { return String(b, charset("GB18030")) }
        return s.removePrefix("\uFEFF")
    }

    private fun looksLikeText(b: ByteArray): Boolean {
        val n = minOf(b.size, 4096)
        if (n == 0) return true
        var bad = 0
        for (i in 0 until n) { val c = b[i].toInt() and 0xFF; if (c == 0) return false; if (c < 9 || c in 14..31) bad++ }
        return bad * 20 < n
    }

    private fun zipEntries(bytes: ByteArray, want: (String) -> Boolean): Map<String, String> {
        val out = sortedMapOf<String, String>(compareBy<String>({ it.length }, { it }))
        ZipInputStream(ByteArrayInputStream(bytes)).use { z ->
            var e = z.nextEntry
            var total = 0L
            while (e != null) {
                if (!e.isDirectory && want(e.name)) {
                    val data = z.readBytes()
                    total += data.size
                    if (total > 64L * 1024 * 1024) break
                    out[e.name] = String(data, Charsets.UTF_8)
                }
                e = z.nextEntry
            }
        }
        return out
    }

    private fun xml(s: String) = Jsoup.parse(s, "", Parser.xmlParser())

    fun docx(bytes: ByteArray): String {
        val doc = zipEntries(bytes) { it == "word/document.xml" }["word/document.xml"] ?: return ""
        val x = xml(doc)
        return x.select("w|p").joinToString("\n") { p ->
            val style = p.selectFirst("w|pStyle")?.attr("w:val").orEmpty()
            val text = p.select("w|t, w|tab").joinToString("") { if (it.tagName() == "w:tab") "\t" else it.text() }
            when {
                text.isBlank() -> ""
                style.startsWith("Heading", true) || style.startsWith("标题") -> "## $text"
                p.selectFirst("w|numPr") != null -> "- $text"
                else -> text
            }
        }
    }

    fun xlsx(bytes: ByteArray): String {
        val parts = zipEntries(bytes) { it == "xl/sharedStrings.xml" || it == "xl/workbook.xml" || (it.startsWith("xl/worksheets/sheet") && it.endsWith(".xml")) }
        val shared = parts["xl/sharedStrings.xml"]?.let { xml(it).select("si").map { si -> si.select("t").joinToString("") { t -> t.text() } } }.orEmpty()
        val names = parts["xl/workbook.xml"]?.let { xml(it).select("sheet").map { s -> s.attr("name") } }.orEmpty()
        val sheets = parts.keys.filter { it.startsWith("xl/worksheets/") }.sortedBy { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
        return sheets.mapIndexed { i, key ->
            val rows = xml(parts.getValue(key)).select("row").take(2000).map { row ->
                row.select("c").joinToString(" | ") { c ->
                    val v = c.selectFirst("v")?.text() ?: c.selectFirst("is t")?.text().orEmpty()
                    if (c.attr("t") == "s") v.toIntOrNull()?.let { shared.getOrNull(it) }.orEmpty() else v
                }
            }.filter { it.replace("|", "").isNotBlank() }
            "## 工作表 ${names.getOrNull(i) ?: (i + 1).toString()}\n" + rows.joinToString("\n")
        }.joinToString("\n\n")
    }

    fun pptx(bytes: ByteArray): String {
        val slides = zipEntries(bytes) { it.startsWith("ppt/slides/slide") && it.endsWith(".xml") }
        return slides.entries.sortedBy { it.key.filter(Char::isDigit).toIntOrNull() ?: 0 }.mapIndexed { i, (_, v) ->
            "## 第 ${i + 1} 页\n" + xml(v).select("a|p").map { p -> p.select("a|t").joinToString("") { it.text() } }.filter { it.isNotBlank() }.joinToString("\n")
        }.joinToString("\n\n")
    }

    fun odf(bytes: ByteArray): String {
        val content = zipEntries(bytes) { it == "content.xml" }["content.xml"] ?: return ""
        return xml(content).select("text|h, text|p, table|table-row").joinToString("\n") { e ->
            if (e.tagName() == "table:table-row") e.select("table|table-cell").joinToString(" | ") { it.text() } else e.text()
        }
    }
}
