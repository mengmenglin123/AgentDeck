package com.huanmeng.huanhermes.core.agent

import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
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

@Serializable
data class ToolCall(val id: String, val name: String, val arguments: JsonObject)

/** Provider-neutral conversation; serializable so a chat survives process death. */
@Serializable
sealed class AgentMessage {
    @Serializable @kotlinx.serialization.SerialName("user")
    data class User(val text: String) : AgentMessage()
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

private suspend fun post(http: OkHttpClient, url: String, headers: Map<String, String>, body: JsonObject): JsonObject {
    val req = Request.Builder().url(url).apply { headers.forEach { (k, v) -> header(k, v) } }
        .post(ProtocolJson.encodeToString(JsonObject.serializer(), body).toRequestBody(JSON)).build()
    val resp = try { http.newCall(req).await() } catch (e: IOException) { throw LlmException("模型服务连接失败：${e.message ?: e.javaClass.simpleName}") }
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

private fun parseArgs(raw: JsonElement?): JsonObject = when (raw) {
    is JsonObject -> raw
    is JsonPrimitive -> raw.contentOrNull?.let { s -> runCatching { ProtocolJson.parseToJsonElement(s.ifBlank { "{}" }).jsonObject }.getOrNull() } ?: JsonObject(emptyMap())
    else -> JsonObject(emptyMap())
}

/** `POST {base}/chat/completions` with function tools: OpenAI and the many services that copy its API. */
class OpenAiCompatClient(private val settings: LlmSettings, private val http: OkHttpClient) : LlmClient {
    override suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): LlmTurn {
        val body = buildJsonObject {
            put("model", settings.effectiveModel)
            put("messages", buildJsonArray {
                add(buildJsonObject { put("role", "system"); put("content", system) })
                messages.forEach { m ->
                    add(when (m) {
                        is AgentMessage.User -> buildJsonObject { put("role", "user"); put("content", m.text) }
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
        val o = post(http, settings.effectiveBaseUrl + "/chat/completions", mapOf("Authorization" to "Bearer ${settings.apiKey.trim()}"), body)
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
    override suspend fun complete(system: String, messages: List<AgentMessage>, tools: List<ToolSpec>): LlmTurn {
        // Consecutive tool results must travel together in one user message.
        val wire = mutableListOf<JsonObject>()
        var pendingResults = mutableListOf<JsonObject>()
        fun flush() { if (pendingResults.isNotEmpty()) { wire += buildJsonObject { put("role", "user"); put("content", JsonArray(pendingResults)) }; pendingResults = mutableListOf() } }
        messages.forEach { m ->
            when (m) {
                is AgentMessage.ToolResult -> pendingResults += buildJsonObject {
                    put("type", "tool_result"); put("tool_use_id", m.callId); put("content", m.content); if (m.isError) put("is_error", true)
                }
                is AgentMessage.User -> { flush(); wire += buildJsonObject { put("role", "user"); put("content", m.text) } }
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
        val body = buildJsonObject {
            put("model", settings.effectiveModel)
            put("max_tokens", 4096)
            put("system", system)
            put("messages", JsonArray(wire))
            if (tools.isNotEmpty()) put("tools", buildJsonArray {
                tools.forEach { t -> add(buildJsonObject { put("name", t.name); put("description", t.description); put("input_schema", t.parameters) }) }
            })
        }
        val o = post(http, settings.effectiveBaseUrl + "/v1/messages", mapOf("x-api-key" to settings.apiKey.trim(), "anthropic-version" to "2023-06-01"), body)
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
