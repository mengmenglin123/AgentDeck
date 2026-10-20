package com.huanmeng.huanhermes.core.agent

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class PhoneToolsTest {
    private fun args(vararg kv: Pair<String, String>) = JsonObject(kv.associate { it.first to JsonPrimitive(it.second) })

    @Test fun jsComputesAndPrints() {
        val (out, err) = JsTool.eval("print('a', 1+1); var x = [1,2,3].map(function(n){return n*n}); x")
        assertFalse(out, err)
        assertTrue(out, out.contains("a 2"))
        assertTrue(out, out.contains("9"))
    }

    @Test fun jsHasNoJavaAccess() {
        val (out, err) = JsTool.eval("java.lang.System.exit(1)")
        assertTrue(out, err)
    }

    @Test fun jsTimesOut() {
        val (out, err) = JsTool.eval("while(true){}", 300)
        assertTrue(out, err); assertTrue(out, out.contains("超时"))
    }

    @Test fun jsReportsSyntaxError() {
        val (out, err) = JsTool.eval("var = ;")
        assertTrue(err); assertTrue(out, out.contains("JavaScript 错误"))
    }

    @Test fun fetchStripsHtml() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(MockResponse().setHeader("Content-Type", "text/html").setBody("<html><head><title>T</title><script>x()</script></head><body><nav>menu</nav><main><h1>Head</h1><p>Para one</p><p>Para two</p><li>item</li></main></body></html>"))
            val (out, err) = WebFetchTool(OkHttpClient()).run(args("url" to s.url("/").toString()))
            assertFalse(out, err)
            assertTrue(out, out.contains("# T")); assertTrue(out, out.contains("## Head")); assertTrue(out, out.contains("- item"))
            assertFalse(out, out.contains("x()")); assertFalse(out, out.contains("menu"))
        }
    }

    @Test fun fetchRejectsBadUrl() = runBlocking {
        assertTrue(WebFetchTool(OkHttpClient()).run(args("url" to "ftp://x")).second)
    }

    @Test fun searchParsesDuckDuckGo() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(MockResponse().setBody("""<div class="result"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa&rut=1">Example A</a><a class="result__snippet">Snippet A</a></div>
                <div class="result"><a class="result__a" href="https://b.org/">B</a></div>"""))
            val (out, err) = WebSearchTool(OkHttpClient(), s.url("/html/").toString()).run(args("query" to "kotlin"))
            assertFalse(out, err)
            assertTrue(out, out.contains("1. Example A")); assertTrue(out, out.contains("https://example.com/a")); assertTrue(out, out.contains("Snippet A"))
            assertTrue(out, out.contains("https://b.org/"))
            assertEquals("kotlin", s.takeRequest().requestUrl?.queryParameter("q"))
        }
    }

    @Test fun clockAnswers() = runBlocking { assertTrue(ClockTool().run(JsonObject(emptyMap())).first.contains("UTC")) }

    private fun zip(vararg files: Pair<String, String>): ByteArray {
        val bo = ByteArrayOutputStream()
        ZipOutputStream(bo).use { z -> files.forEach { (n, c) -> z.putNextEntry(ZipEntry(n)); z.write(c.toByteArray()); z.closeEntry() } }
        return bo.toByteArray()
    }

    @Test fun docxText() {
        val x = """<w:document xmlns:w="w"><w:body><w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>标题</w:t></w:r></w:p><w:p><w:r><w:t>正文</w:t></w:r><w:r><w:t>第二段</w:t></w:r></w:p></w:body></w:document>"""
        val t = DocumentText.extract("a.docx", "", zip("word/document.xml" to x))!!
        assertTrue(t, t.contains("## 标题")); assertTrue(t, t.contains("正文第二段"))
    }

    @Test fun xlsxText() {
        val shared = """<sst><si><t>名字</t></si><si><t>张三</t></si></sst>"""
        val sheet = """<worksheet><sheetData><row><c t="s"><v>0</v></c><c><v>年龄</v></c></row><row><c t="s"><v>1</v></c><c><v>30</v></c></row></sheetData></worksheet>"""
        val wb = """<workbook><sheets><sheet name="人员"/></sheets></workbook>"""
        val t = DocumentText.extract("a.xlsx", "", zip("xl/sharedStrings.xml" to shared, "xl/workbook.xml" to wb, "xl/worksheets/sheet1.xml" to sheet))!!
        assertTrue(t, t.contains("工作表 人员")); assertTrue(t, t.contains("张三 | 30"))
    }

    @Test fun pptxText() {
        val s1 = """<p:sld xmlns:a="a" xmlns:p="p"><a:p><a:r><a:t>第一页</a:t></a:r></a:p></p:sld>"""
        val t = DocumentText.extract("a.pptx", "", zip("ppt/slides/slide1.xml" to s1))!!
        assertTrue(t, t.contains("第 1 页")); assertTrue(t, t.contains("第一页"))
    }

    @Test fun plainAndBinary() {
        assertEquals("hello", DocumentText.extract("a.kt", "", "hello".toByteArray()))
        assertEquals(null, DocumentText.extract("a.bin", "", byteArrayOf(0, 1, 2, 3)))
        assertEquals(null, DocumentText.extract("a.pdf", "application/pdf", byteArrayOf(1)))
        assertEquals("pdf text", DocumentText.extract("a.pdf", "application/pdf", byteArrayOf(1)) { "pdf text" })
    }

    @Test fun userMessageCarriesDocsAndImages() {
        val m = AgentMessage.User("看看", listOf(AgentAttachment("a.txt", text = "内容"), AgentAttachment("p.jpg", "image/jpeg", imageBase64 = "QUJD")))
        assertTrue(m.modelText().contains("[附件：a.txt]\n内容"))
        assertEquals(listOf("image/jpeg" to "QUJD"), m.images)
    }

    @Test fun skillPacksHaveUniqueIds() {
        assertEquals(SkillPacks.all.size, SkillPacks.all.map { it.id }.toSet().size)
        assertTrue(SkillPacks.all.all { it.starters.isNotEmpty() })
    }
}
