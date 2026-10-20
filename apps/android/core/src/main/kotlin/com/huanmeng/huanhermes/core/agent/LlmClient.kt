package com.huanmeng.huanhermes.core.agent

import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@Serializable
enum class LlmProvider(val label: String, val defaultBaseUrl: String, val defaultModel: String) {
    OPENAI("OpenAI 兼容（DeepSeek、通义、Kimi、OpenRouter…）", "https://api.openai.com/v1", "gpt-4o-mini"),
    ANTHROPIC("Anthropic Claude", "https://api.anthropic.com", "claude-sonnet-4-5"),
}

/** A file the user attached: documents carry extracted [text], pictures a downscaled JPEG/PNG in [imageBase64]. */
@Serializable
data class AgentAttachment(
    val name: String,
    val mime: String = "application/octet-stream",
    val text: String? = null,
    val imageBase64: String? = null,
    val size: Long = 0,
)

@Serializable
data class ToolCall(val id: String, val name: String, val arguments: JsonObject)

/** Provider-neutral conversation; serializable so a chat survives process death. */
@Serializable
sealed class AgentMessage {
    @Serializable @kotlinx.serialization.SerialName("user")
    data class User(val text: String, val attachments: List<AgentAttachment> = emptyList()) : AgentMessage() {
        /** What the model reads: typed text plus every document's extracted text. */
        fun modelText(): String = buildString {
            append(text)
            attachments.filter { it.text != null }.forEach { a ->
                append("\n\n[附件：").append(a.name).append("]\n").append(a.text)
            }
        }.trim()
        val images get() = attachments.mapNotNull { a -> a.imageBase64?.let { a.mime to it } }
    }
    @Serializable @kotlinx.serialization.SerialName("assistant")
    data class Assistant(val text: String, val toolCalls: List<ToolCall> = emptyList()) : AgentMessage()
    @Serializable @kotlinx.serialization.SerialName("tool")
    data class ToolResult(val callId: String, val name: String, val content: String, val isError: Boolean = false) : AgentMessage()
}

data class ToolSpec(val name: String, val description: String, val parameters: JsonObject)

data class LlmTurn(val text: String, val toolCalls: List<ToolCall>)

class LlmException(message: String) : Exception(message)

interface LlmClient {
    suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): LlmTurn

    /** Streams assistant text through [onDelta]; the default falls back to one non-streaming call. */
    suspend fun stream(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>, onDelta: (String) -> Unit): LlmTurn =
        complete(system, messages, tools).also { if (it.text.isNotEmpty()) onDelta(it.text) }
}

@Serializable
data class LlmSettings(
    val provider: LlmProvider = LlmProvider.OPENAI,
    val baseUrl: String = "",
    val model: String = "",
    val apiKey: String = "",
) {
    val effectiveBaseUrl get() = baseUrl.trim().trimEnd('/').ifEmpty { provider.defaultBaseUrl }
    val effectiveModel get() = model.trim().ifEmpty { provider.defaultModel }
    val configured get() = apiKey.isNotBlank()
}

fun llmClientFor(settings: LlmSettings, http: OkHttpClient): LlmClient = when (settings.provider) {
    LlmProvider.OPENAI -> OpenAiCompatClient(settings, http)
    LlmProvider.ANTHROPIC -> AnthropicClient(settings, http)
}

private val JSON = "application/json; charset=utf-8".toMediaType()

internal suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) { if (cont.isActive) cont.resumeWithException(e) }
        override fun onResponse(call: Call, response: Response) { cont.resume(response) }
    })
}

private fun request(url: String, headers: Map<String, String>, body: JsonObject, sse: Boolean = false): Request =
    Request.Builder().url(url).apply { headers.forEach { (k, v) -> header(k, v) }; if (sse) header("Accept", "text/event-stream") }
        .post(ProtocolJson.encodeToString(JsonObject.serializer(), body).toRequestBody(JSON)).build()

private suspend fun open(http: OkHttpClient, req: Request): Pair<Call, Response> {
    val call = http.newCall(req)
    val resp = try { call.await() } catch (e: IOException) { throw LlmException("模型服务连接失败：${e.message ?: e.javaClass.simpleName}") }
    return call to resp
}

internal suspend fun getJson(http: OkHttpClient, req: Request): JsonObject = readJson(open(http, req).second)

private suspend fun post(http: OkHttpClient, url: String, headers: Map<String, String>, body: JsonObject): JsonObject {
    val (_, resp) = open(http, request(url, headers, body))
    return readJson(resp)
}

private suspend fun readJson(resp: Response): JsonObject {
    val text = withContext(Dispatchers.IO) { resp.use { it.body?.string().orEmpty() } }
    if (!resp.isSuccessful) {
        val msg = runCatching {
            val o = ProtocolJson.parseToJsonElement(text).jsonObject
            ((o["error"] as? JsonObject)?.get("message") as? JsonPrimitive)?.contentOrNull ?: (o["message"] as? JsonPrimitive)?.contentOrNull
        }.getOrNull() ?: text.take(200)
        throw LlmException(when (resp.code) {
            401, 403 -> "API Key 无效或没有权限（${resp.code}）：$msg"
            404 -> "接口地址或模型名不对（404）：$msg"
            429 -> "请求太频繁或额度不足（429）：$msg"
            else -> "模型服务返回 ${resp.code}：$msg"
        })
    }
    return runCatching { ProtocolJson.parseToJsonElement(text).jsonObject }.getOrElse { throw LlmException("模型服务返回了无法解析的内容") }
}

/**
 * POSTs with stream=true and feeds every SSE `data:` payload to [onEvent].
 * Returns null after a stream, or the plain JSON body when the server ignored
 * `stream` (some proxies do). Cancelling the coroutine aborts the request.
 */
private suspend fun streamEvents(http: OkHttpClient, req: Request, onEvent: (JsonObject) -> Unit): JsonObject? {
    val (call, resp) = open(http, req)
    val type = resp.header("Content-Type").orEmpty()
    if (!resp.isSuccessful || !type.contains("event-stream")) return readJson(resp)
    try {
        runInterruptible(Dispatchers.IO) {
            resp.use { r ->
                val src = r.body!!.source()
                while (true) {
                    val line = src.readUtf8Line() ?: break
                    if (!line.startsWith("data:")) continue
                    val data = line.removePrefix("data:").trim()
                    if (data == "[DONE]") break
                    val o = runCatching { ProtocolJson.parseToJsonElement(data).jsonObject }.getOrNull() ?: continue
                    (o["error"] as? JsonObject)?.let { e -> throw LlmException("模型服务出错：" + ((e["message"] as? JsonPrimitive)?.contentOrNull ?: e.toString().take(200))) }
                    onEvent(o)
                }
            }
        }
    } catch (e: IOException) {
        throw LlmException("流式响应中断：${e.message ?: e.javaClass.simpleName}")
    } finally {
        call.cancel()
    }
    return null
}

private fun parseArgs(raw: JsonElement?): JsonObject = when (raw) {
    is JsonObject -> raw
    is JsonPrimitive -> raw.contentOrNull?.let { s -> runCatching { ProtocolJson.parseToJsonElement(s.ifBlank { "{}" }).jsonObject }.getOrNull() } ?: JsonObject(emptyMap())
    else -> JsonObject(emptyMap())
}

/** `POST {base}/chat/completions` with function tools: OpenAI and the many services that copy its API. */
class OpenAiCompatClient(private val settings: LlmSettings, private val http: OkHttpClient) : LlmClient {
    private val url get() = settings.effectiveBaseUrl + "/chat/completions"
    private val headers get() = mapOf("Authorization" to "Bearer ${settings.apiKey.trim()}")

    override suspend fun stream(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>, onDelta: (String) -> Unit): LlmTurn {
        val text = StringBuilder()
        class Partial(var id: String = "", var name: String = "", val args: StringBuilder = StringBuilder())
        val calls = sortedMapOf<Int, Partial>()
        val body = JsonObject(body(system, messages, tools) + mapOf("stream" to JsonPrimitive(true)))
        val plain = streamEvents(http, request(url, headers, body, sse = true)) { o ->
            val delta = ((o["choices"] as? JsonArray)?.firstOrNull() as? JsonObject)?.get("delta") as? JsonObject ?: return@streamEvents
            (delta["content"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { text.append(it); onDelta(it) }
            (delta["tool_calls"] as? JsonArray)?.forEach { el ->
                val c = el as? JsonObject ?: return@forEach
                val i = (c["index"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull() ?: calls.size
                val p = calls.getOrPut(i) { Partial() }
                (c["id"] as? JsonPrimitive)?.contentOrNull?.let { if (it.isNotEmpty()) p.id = it }
                (c["function"] as? JsonObject)?.let { f ->
                    (f["name"] as? JsonPrimitive)?.contentOrNull?.let { p.name += it }
                    (f["arguments"] as? JsonPrimitive)?.contentOrNull?.let { p.args.append(it) }
                }
            }
        }
        if (plain != null) return parse(plain).also { if (it.text.isNotEmpty()) onDelta(it.text) }
        return LlmTurn(text.toString(), calls.entries.filter { it.value.name.isNotEmpty() }.map { (i, p) ->
            ToolCall(p.id.ifEmpty { "call_$i" }, p.name, parseArgs(JsonPrimitive(p.args.toString())))
        })
    }

    override suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): LlmTurn =
        parse(post(http, url, headers, body(system, messages, tools)))

    private fun body(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): JsonObject {
        return buildJsonObject {
            put("model", settings.effectiveModel)
            put("messages", buildJsonArray {
                add(buildJsonObject { put("role", "system"); put("content", system) })
                messages.forEach { m ->
                    add(when (m) {
                        is AgentMessage.User -> buildJsonObject {
                            put("role", "user")
                            val imgs = m.images
                            if (imgs.isEmpty()) put("content", m.modelText()) else put("content", buildJsonArray {
                                add(buildJsonObject { put("type", "text"); put("text", m.modelText().ifEmpty { "（见图片）" }) })
                                imgs.forEach { (mime, b64) -> add(buildJsonObject { put("type", "image_url"); put("image_url", buildJsonObject { put("url", "data:$mime;base64,$b64") }) }) }
                            })
                        }
                        is AgentMessage.Assistant -> buildJsonObject {
                            put("role", "assistant"); put("content", m.text)
                            if (m.toolCalls.isNotEmpty()) put("tool_calls", buildJsonArray {
                                m.toolCalls.forEach { c ->
                                    add(buildJsonObject {
                                        put("id", c.id); put("type", "function")
                                        put("function", buildJsonObject { put("name", c.name); put("arguments", ProtocolJson.encodeToString(JsonObject.serializer(), c.arguments)) })
                                    })
                                }
                            })
                        }
                        is AgentMessage.ToolResult -> buildJsonObject { put("role", "tool"); put("tool_call_id", m.callId); put("content", m.content) }
                    })
                }
            })
            if (tools.isNotEmpty()) put("tools", buildJsonArray {
                tools.forEach { t -> add(buildJsonObject { put("type", "function"); put("function", buildJsonObject { put("name", t.name); put("description", t.description); put("parameters", t.parameters) }) }) }
            })
        }
    }

    private fun parse(o: JsonObject): LlmTurn {
        val msg = (o["choices"] as? JsonArray)?.firstOrNull()?.jsonObject?.get("message") as? JsonObject
            ?: throw LlmException("模型没有返回回答")
        val text = (msg["content"] as? JsonPrimitive)?.contentOrNull.orEmpty()
        val calls = (msg["tool_calls"] as? JsonArray).orEmpty().mapIndexedNotNull { i, el ->
            val c = el as? JsonObject ?: return@mapIndexedNotNull null
            val fn = c["function"] as? JsonObject ?: return@mapIndexedNotNull null
            val name = (fn["name"] as? JsonPrimitive)?.contentOrNull ?: return@mapIndexedNotNull null
            ToolCall((c["id"] as? JsonPrimitive)?.contentOrNull ?: "call_$i", name, parseArgs(fn["arguments"]))
        }
        return LlmTurn(text, calls)
    }
}

/** Anthropic Messages API with tool_use / tool_result blocks. */
class AnthropicClient(private val settings: LlmSettings, private val http: OkHttpClient) : LlmClient {
    private val url get() = settings.effectiveBaseUrl + "/v1/messages"
    private val headers get() = mapOf("x-api-key" to settings.apiKey.trim(), "anthropic-version" to "2023-06-01")

    override suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): LlmTurn =
        parse(post(http, url, headers, body(system, messages, tools)))

    override suspend fun stream(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>, onDelta: (String) -> Unit): LlmTurn {
        val text = StringBuilder()
        class Block(val type: String, val id: String, val name: String, val json: StringBuilder = StringBuilder())
        val blocks = sortedMapOf<Int, Block>()
        val body = JsonObject(body(system, messages, tools) + mapOf("stream" to JsonPrimitive(true)))
        val plain = streamEvents(http, request(url, headers, body, sse = true)) { o ->
            fun str(obj: JsonObject?, k: String) = (obj?.get(k) as? JsonPrimitive)?.contentOrNull
            val i = str(o, "index")?.toIntOrNull() ?: 0
            when (str(o, "type")) {
                "content_block_start" -> {
                    val b = o["content_block"] as? JsonObject
                    blocks[i] = Block(str(b, "type").orEmpty(), str(b, "id").orEmpty(), str(b, "name").orEmpty())
                }
                "content_block_delta" -> {
                    val d = o["delta"] as? JsonObject
                    when (str(d, "type")) {
                        "text_delta" -> str(d, "text")?.let { text.append(it); onDelta(it) }
                        "input_json_delta" -> str(d, "partial_json")?.let { blocks[i]?.json?.append(it) }
                    }
                }
            }
        }
        if (plain != null) return parse(plain).also { if (it.text.isNotEmpty()) onDelta(it.text) }
        return LlmTurn(text.toString(), blocks.values.filter { it.type == "tool_use" && it.name.isNotEmpty() }.mapIndexed { n, b ->
            ToolCall(b.id.ifEmpty { "toolu_$n" }, b.name, parseArgs(JsonPrimitive(b.json.toString())))
        })
    }

    private fun body(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): JsonObject {
        // Consecutive tool results must travel together in one user message.
        val wire = mutableListOf<JsonObject>()
        var pendingResults = mutableListOf<JsonObject>()
        fun flush() { if (pendingResults.isNotEmpty()) { wire += buildJsonObject { put("role", "user"); put("content", JsonArray(pendingResults)) }; pendingResults = mutableListOf() } }
        messages.forEach { m ->
            when (m) {
                is AgentMessage.ToolResult -> pendingResults += buildJsonObject {
                    put("type", "tool_result"); put("tool_use_id", m.callId); put("content", m.content); if (m.isError) put("is_error", true)
                }
                is AgentMessage.User -> {
                    flush()
                    wire += buildJsonObject {
                        put("role", "user")
                        val imgs = m.images
                        if (imgs.isEmpty()) put("content", m.modelText()) else put("content", buildJsonArray {
                            imgs.forEach { (mime, b64) -> add(buildJsonObject { put("type", "image"); put("source", buildJsonObject { put("type", "base64"); put("media_type", mime); put("data", b64) }) }) }
                            add(buildJsonObject { put("type", "text"); put("text", m.modelText().ifEmpty { "（见图片）" }) })
                        })
                    }
                }
                is AgentMessage.Assistant -> {
                    flush()
                    wire += buildJsonObject {
                        put("role", "assistant")
                        put("content", buildJsonArray {
                            if (m.text.isNotBlank()) add(buildJsonObject { put("type", "text"); put("text", m.text) })
                            m.toolCalls.forEach { c -> add(buildJsonObject { put("type", "tool_use"); put("id", c.id); put("name", c.name); put("input", c.arguments) }) }
                        })
                    }
                }
            }
        }
        flush()
        return buildJsonObject {
            put("model", settings.effectiveModel)
            put("max_tokens", 4096)
            put("system", system)
            put("messages", JsonArray(wire))
            if (tools.isNotEmpty()) put("tools", buildJsonArray {
                tools.forEach { t -> add(buildJsonObject { put("name", t.name); put("description", t.description); put("input_schema", t.parameters) }) }
            })
        }
    }

    private fun parse(o: JsonObject): LlmTurn {
        val blocks = (o["content"] as? JsonArray) ?: throw LlmException("模型没有返回回答")
        val text = StringBuilder(); val calls = mutableListOf<ToolCall>()
        blocks.forEach { el ->
            val b = el as? JsonObject ?: return@forEach
            when ((b["type"] as? JsonPrimitive)?.contentOrNull) {
                "text" -> text.append((b["text"] as? JsonPrimitive)?.contentOrNull.orEmpty())
                "tool_use" -> calls += ToolCall(
                    (b["id"] as? JsonPrimitive)?.contentOrNull ?: "toolu_${calls.size}",
                    (b["name"] as? JsonPrimitive)?.contentOrNull ?: return@forEach,
                    parseArgs(b["input"]),
                )
            }
        }
        return LlmTurn(text.toString(), calls)
    }
}

internal fun JsonArray?.orEmpty(): List<JsonElement> = this ?: emptyList()
