package com.huanmeng.huanhermes.core.agent

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.mozilla.javascript.Context
import org.mozilla.javascript.ContextFactory
import org.mozilla.javascript.ScriptableObject
import org.mozilla.javascript.Undefined
import java.net.URLDecoder
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * A tool that runs on the phone itself (no SSH): web, a sandboxed JS
 * interpreter, the clock. [readOnly] tools run without asking under
 * [ApprovalPolicy.SAFE_AUTO].
 */
interface PhoneTool {
    val spec: ToolSpec
    val readOnly: Boolean
    fun summarize(args: JsonObject): String
    /** Returns the text for the model and whether it is an error. */
    suspend fun run(args: JsonObject): Pair<String, Boolean>
}

private fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull.orEmpty()
private fun schema(vararg props: Pair<String, String>, required: List<String> = props.map { it.first }) = buildJsonObject {
    put("type", "object")
    put("properties", buildJsonObject { props.forEach { (k, d) -> put(k, buildJsonObject { put("type", "string"); put("description", d) }) } })
    put("required", buildJsonArray { required.forEach { add(JsonPrimitive(it)) } })
}
private fun clipText(s: String, max: Int) = if (s.length <= max) s else s.take(max) + "\n…（已截断，共 ${s.length} 字符）"

private const val UA = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36 AgentDeck"

/** Fetches a page and returns its readable text (scripts, nav and styles dropped). */
class WebFetchTool(private val http: OkHttpClient) : PhoneTool {
    override val readOnly = true
    override val spec = ToolSpec("web_fetch", "抓取一个网页（http/https），返回标题和正文纯文本（最多约 12000 字符），也可读取 JSON/纯文本接口。",
        schema("url" to "完整网址，以 http:// 或 https:// 开头"))
    override fun summarize(args: JsonObject) = "打开 " + args.str("url")
    override suspend fun run(args: JsonObject): Pair<String, Boolean> {
        val url = args.str("url").trim().toHttpUrlOrNull() ?: return "网址无效：${args.str("url")}" to true
        if (url.scheme != "http" && url.scheme != "https") return "只支持 http/https" to true
        return runInterruptible(Dispatchers.IO) {
            http.newCall(Request.Builder().url(url).header("User-Agent", UA).build()).execute().use { resp ->
                val body = resp.body ?: return@use "空响应（HTTP ${resp.code}）" to true
                val type = body.contentType()?.toString().orEmpty()
                val raw = body.source().let { src -> src.request(2_000_000); src.buffer.clone().readUtf8() }
                val text = if (type.contains("html") || raw.trimStart().startsWith("<")) htmlToText(raw, url.toString()) else raw
                "HTTP ${resp.code} ${url}\n" + clipText(text, 12_000) to !resp.isSuccessful
            }
        }
    }

    companion object {
        fun htmlToText(html: String, base: String = ""): String {
            val doc = Jsoup.parse(html, base)
            doc.select("script, style, noscript, svg, nav, footer, header, form, iframe").remove()
            val title = doc.title()
            val main = doc.selectFirst("article, main, [role=main]") ?: doc.body() ?: doc
            val lines = main.select("h1, h2, h3, h4, p, li, pre, td, blockquote").map { e ->
                val t = e.text().trim()
                when (e.tagName()) { "h1", "h2", "h3", "h4" -> "## $t"; "li" -> "- $t"; else -> t }
            }.filter { it.isNotBlank() && it != "- " }.distinct()
            val body = if (lines.size >= 3) lines.joinToString("\n") else main.text()
            return (if (title.isNotBlank()) "# $title\n" else "") + body
        }
    }
}

/** Web search through DuckDuckGo's HTML endpoint (no key needed). */
class WebSearchTool(private val http: OkHttpClient, private val endpoint: String = "https://html.duckduckgo.com/html/") : PhoneTool {
    override val readOnly = true
    override val spec = ToolSpec("web_search", "联网搜索，返回前 8 条结果（标题、网址、摘要）。需要细节时再用 web_fetch 打开具体网页。",
        schema("query" to "搜索关键词"))
    override fun summarize(args: JsonObject) = "搜索 " + args.str("query")
    override suspend fun run(args: JsonObject): Pair<String, Boolean> {
        val q = args.str("query").trim().ifEmpty { return "query 不能为空" to true }
        val url = endpoint.toHttpUrlOrNull()!!.newBuilder().addQueryParameter("q", q).build()
        return runInterruptible(Dispatchers.IO) {
            http.newCall(Request.Builder().url(url).header("User-Agent", UA).build()).execute().use { resp ->
                val html = resp.body?.string().orEmpty()
                val results = parseResults(html)
                if (results.isEmpty()) "没有搜到结果（HTTP ${resp.code}）" to !resp.isSuccessful
                else results.take(8).mapIndexed { i, r -> "${i + 1}. ${r.first}\n   ${r.second}\n   ${r.third}" }.joinToString("\n") to false
            }
        }
    }

    companion object {
        /** (title, url, snippet) from a DuckDuckGo HTML result page. */
        fun parseResults(html: String): List<Triple<String, String, String>> =
            Jsoup.parse(html).select(".result, .web-result").mapNotNull { r ->
                val a = r.selectFirst("a.result__a") ?: return@mapNotNull null
                var href = a.attr("href")
                // Result links are redirects: //duckduckgo.com/l/?uddg=<encoded target>
                Regex("[?&]uddg=([^&]+)").find(href)?.let { href = URLDecoder.decode(it.groupValues[1], "UTF-8") }
                if (href.startsWith("//")) href = "https:$href"
                Triple(a.text(), href, r.selectFirst(".result__snippet")?.text().orEmpty())
            }.filter { it.first.isNotBlank() && !it.second.contains("duckduckgo.com/y.js") }
    }
}

/**
 * Runs JavaScript in Rhino's interpreter with only the standard objects: no
 * Java access, no files, no network. Bounded by instruction count and time.
 */
class JsTool(private val timeoutMs: Long = 5_000) : PhoneTool {
    override val readOnly = true
    override val spec = ToolSpec("run_javascript", "在手机上的沙箱里执行一段 JavaScript（ES5/部分 ES6，无网络、无文件），适合计算、数据处理、日期换算、正则、JSON 转换。用 print(...) 输出，最后一个表达式的值也会返回。",
        schema("code" to "要执行的 JavaScript 代码"))
    override fun summarize(args: JsonObject) = args.str("code").lineSequence().firstOrNull { it.isNotBlank() }?.take(80) ?: "JavaScript"
    override suspend fun run(args: JsonObject): Pair<String, Boolean> {
        val code = args.str("code").ifBlank { return "code 不能为空" to true }
        return runInterruptible(Dispatchers.Default) { eval(code, timeoutMs) }
    }

    private class Timeout : RuntimeException("执行超时")

    companion object {
        private val factory = object : ContextFactory() {
            override fun observeInstructionCount(cx: Context, instructionCount: Int) {
                val deadline = cx.getThreadLocal("deadline") as? Long ?: return
                if (System.currentTimeMillis() > deadline || Thread.currentThread().isInterrupted) throw Timeout()
            }
        }

        fun eval(code: String, timeoutMs: Long = 5_000): Pair<String, Boolean> {
            val cx = factory.enterContext()
            return try {
                cx.optimizationLevel = -1 // interpreter: works on Android, honours instruction observer
                cx.languageVersion = Context.VERSION_ES6
                cx.instructionObserverThreshold = 10_000
                cx.putThreadLocal("deadline", System.currentTimeMillis() + timeoutMs)
                val scope = cx.initSafeStandardObjects()
                val out = StringBuilder()
                val print = object : org.mozilla.javascript.BaseFunction() {
                    override fun call(c: Context, s: org.mozilla.javascript.Scriptable, t: org.mozilla.javascript.Scriptable?, a: Array<out Any?>): Any {
                        if (out.length < 20_000) out.append(a.joinToString(" ") { Context.toString(it) }).append('\n')
                        return Undefined.instance
                    }
                }
                ScriptableObject.putProperty(scope, "print", print)
                ScriptableObject.putProperty(scope, "console", cx.newObject(scope).also { ScriptableObject.putProperty(it, "log", print) })
                val result = cx.evaluateString(scope, code, "agent.js", 1, null)
                val shown = when {
                    result == null || result is Undefined -> ""
                    result is org.mozilla.javascript.Scriptable -> runCatching {
                        org.mozilla.javascript.NativeJSON.stringify(cx, scope, result, null, 2)?.let { Context.toString(it) }
                    }.getOrNull() ?: Context.toString(result)
                    else -> Context.toString(result)
                }
                val text = buildString {
                    if (out.isNotEmpty()) append(out.toString().trimEnd())
                    if (shown.isNotEmpty() && shown != "undefined") { if (isNotEmpty()) append("\n"); append("=> ").append(shown) }
                    if (isEmpty()) append("（无输出）")
                }
                clipText(text, 12_000) to false
            } catch (e: Timeout) {
                "执行超时（${timeoutMs / 1000} 秒）" to true
            } catch (e: org.mozilla.javascript.RhinoException) {
                "JavaScript 错误：${e.details()}（第 ${e.lineNumber()} 行）" to true
            } catch (e: Exception) {
                (e.message ?: e.javaClass.simpleName) to true
            } finally {
                Context.exit()
            }
        }
    }
}

/** Current date/time in the phone's zone (models have no clock). */
class ClockTool : PhoneTool {
    override val readOnly = true
    override val spec = ToolSpec("current_time", "获取手机当前的日期、时间、星期和时区。", schema())
    override fun summarize(args: JsonObject) = "查看当前时间"
    override suspend fun run(args: JsonObject): Pair<String, Boolean> {
        val now = ZonedDateTime.now()
        return now.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss EEEE")) + " " + now.zone.id + " (UTC" + now.offset.id.replace("Z", "+00:00") + ")" to false
    }
}

object PhoneTools {
    fun defaults(http: OkHttpClient, web: Boolean = true, js: Boolean = true): List<PhoneTool> = buildList {
        add(ClockTool())
        if (web) { add(WebSearchTool(http)); add(WebFetchTool(http)) }
        if (js) add(JsTool())
    }
}
