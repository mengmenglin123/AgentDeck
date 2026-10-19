package com.huanmeng.huanhermes.core.agent

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.UUID

/** One saved model provider (RikkaHub-style): its own endpoint, key and model list. */
@Serializable
data class ProviderConfig(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val type: LlmProvider = LlmProvider.OPENAI,
    val baseUrl: String = "",
    val apiKey: String = "",
    val models: List<String> = emptyList(),
    val enabled: Boolean = true,
) {
    fun settings(model: String) = LlmSettings(type, baseUrl, model, apiKey)
    val effectiveBaseUrl get() = settings("").effectiveBaseUrl
}

/** Presets for "添加供应商". */
object ProviderPresets {
    data class Preset(val name: String, val type: LlmProvider, val baseUrl: String, val models: List<String>)
    val all = listOf(
        Preset("OpenAI", LlmProvider.OPENAI, "https://api.openai.com/v1", listOf("gpt-4o-mini", "gpt-4.1")),
        Preset("DeepSeek", LlmProvider.OPENAI, "https://api.deepseek.com/v1", listOf("deepseek-chat")),
        Preset("通义千问", LlmProvider.OPENAI, "https://dashscope.aliyuncs.com/compatible-mode/v1", listOf("qwen-plus", "qwen-max")),
        Preset("Kimi", LlmProvider.OPENAI, "https://api.moonshot.cn/v1", listOf("kimi-k2-0905-preview")),
        Preset("智谱", LlmProvider.OPENAI, "https://open.bigmodel.cn/api/paas/v4", listOf("glm-4.6")),
        Preset("OpenRouter", LlmProvider.OPENAI, "https://openrouter.ai/api/v1", emptyList()),
        Preset("Claude", LlmProvider.ANTHROPIC, "https://api.anthropic.com", listOf("claude-sonnet-4-5")),
        Preset("自定义", LlmProvider.OPENAI, "", emptyList()),
    )
}

/** Picks (provider, model); falls back to the first enabled provider's first model. */
data class ModelChoice(val provider: ProviderConfig, val model: String)

fun resolveModel(providers: List<ProviderConfig>, providerId: String?, model: String?): ModelChoice? {
    val enabled = providers.filter { it.enabled && it.apiKey.isNotBlank() }
    enabled.firstOrNull { it.id == providerId }?.let { p ->
        val m = model?.takeIf { it.isNotBlank() } ?: p.models.firstOrNull() ?: p.type.defaultModel
        return ModelChoice(p, m)
    }
    val p = enabled.firstOrNull() ?: return null
    return ModelChoice(p, p.models.firstOrNull() ?: p.type.defaultModel)
}

/** GET the provider's model list (OpenAI `/models`, Anthropic `/v1/models`), sorted. */
suspend fun fetchModels(p: ProviderConfig, http: OkHttpClient): List<String> {
    val base = p.effectiveBaseUrl
    val req = Request.Builder().get().apply {
        when (p.type) {
            LlmProvider.OPENAI -> url("$base/models").header("Authorization", "Bearer ${p.apiKey.trim()}")
            LlmProvider.ANTHROPIC -> url("$base/v1/models?limit=100").header("x-api-key", p.apiKey.trim()).header("anthropic-version", "2023-06-01")
        }
    }.build()
    val o = getJson(http, req)
    val data = (o["data"] as? JsonArray) ?: (o["models"] as? JsonArray) ?: throw LlmException("接口没有返回模型列表")
    return data.mapNotNull { ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.contentOrNull }.distinct().sorted()
}
