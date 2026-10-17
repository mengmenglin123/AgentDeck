package com.huanmeng.huanhermes.core.net

import com.huanmeng.huanhermes.core.mgmt.HttpEngine
import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/** A scanned/pasted `huanhermes://connect?...` link, possibly with a one-time `code`. */
data class PairingLink(val config: HostConfig, val code: String?, val name: String?) {
    val needsClaim get() = !config.hasTokens && !code.isNullOrBlank()

    companion object {
        fun parse(raw: String): PairingLink? {
            val config = HostConfig.parsePairingUri(raw) ?: return null
            val params = HostConfig.pairingParams(raw)
            return PairingLink(config, params["code"]?.trim()?.takeIf { it.isNotEmpty() }, params["name"]?.trim()?.takeIf { it.isNotEmpty() }?.take(40))
        }
    }
}

object Pairing {
    /**
     * Trades the one-time code for this device's own tokens
     * (`POST /api/v1/pairing/claim`, no bearer token).
     */
    suspend fun claim(link: PairingLink, engine: HttpEngine, deviceName: String): HostConfig {
        val code = link.code ?: throw HostError.Protocol("配对链接里没有配对码")
        val body = buildJsonObject {
            put("code", code); put("device_id", link.config.deviceId); put("name", deviceName.take(64))
        }
        val raw = engine.execute(
            "POST", link.config.mgmtBaseUrl + "/pairing/claim",
            mapOf("Content-Type" to "application/json", "Accept" to "application/json"), body.toString().toByteArray(),
        )
        val obj = runCatching { ProtocolJson.parseToJsonElement(String(raw.body, Charsets.UTF_8)).jsonObject }.getOrNull()
        if (raw.status == 403) throw HostError.Auth("配对码无效或已过期，请在 Host 上重新运行 pair")
        if (raw.status == 404) throw HostError.Http(404, "这个 Host 不支持配对码，请升级 companion 或手动填写令牌")
        if (raw.status !in 200..299 || obj == null) throw HostError.Http(raw.status, "配对失败（HTTP ${raw.status}）")
        val data = obj["data"] as? JsonObject ?: throw HostError.Protocol("配对响应缺少 data")
        fun s(k: String) = (data[k] as? JsonPrimitive)?.contentOrNull.orEmpty()
        val bridgeToken = s("bridge_token"); val mgmtToken = s("mgmt_token")
        if (bridgeToken.isEmpty() || mgmtToken.isEmpty()) throw HostError.Protocol("配对响应缺少令牌")
        return link.config.copy(
            bridgeToken = bridgeToken, mgmtToken = mgmtToken,
            bridgePort = (data["bridge_port"] as? JsonPrimitive)?.intOrNull?.takeIf { HostConfig.validPort(it) } ?: link.config.bridgePort,
        )
    }
}
