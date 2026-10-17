package com.huanmeng.huanhermes.core.net

import kotlinx.serialization.Serializable
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.UUID

/** One Host connection (mirrors Flutter ConnectionConfig so profiles migrate 1:1). */
@Serializable
data class HostConfig(
    val host: String = "127.0.0.1",
    val bridgePort: Int = 9810,
    val mgmtPort: Int = 9820,
    val bridgeToken: String = "",
    val mgmtToken: String = "",
    val useTls: Boolean = false,
    val platformName: String = "huanhermes-app",
    val deviceId: String = newDeviceId(),
    /** TLS certificate pin: base64 SHA-256 of the server's public key (SPKI); allows self-signed. */
    val certPin: String = "",
) {
    val secrets: List<String> get() = listOf(bridgeToken, mgmtToken).filter { it.isNotEmpty() }
    val hasTokens: Boolean get() = bridgeToken.isNotEmpty() && mgmtToken.isNotEmpty()

    /** Host for a URL authority: IPv6 literals are bracketed. */
    val urlHost: String get() = formatHost(host)

    val bridgeWsUrl: String
        get() = "${if (useTls) "wss" else "ws"}://$urlHost:$bridgePort/bridge/ws?token=${encode(bridgeToken)}"

    val bridgeWsUrlRedacted: String
        get() = "${if (useTls) "wss" else "ws"}://$urlHost:$bridgePort/bridge/ws?token=${Redactor.MASK}"

    val mgmtBaseUrl: String get() = "${if (useTls) "https" else "http"}://$urlHost:$mgmtPort/api/v1"

    fun sessionKeyFor(conversationId: String) = "huan:$deviceId:$conversationId"

    /** Field problems a form should show; empty when the config is usable. */
    fun validate(): List<String> = buildList {
        val h = host.trim()
        if (h.isEmpty()) add("Host 不能为空")
        else if (h.any { it.isWhitespace() || it in "/?#@" }) add("Host 格式不正确")
        if (!validPort(bridgePort)) add("Bridge 端口必须在 1–65535 之间")
        if (!validPort(mgmtPort)) add("Management 端口必须在 1–65535 之间")
        if (!hasTokens) add("需要填写 Bridge 和 Management 令牌")
    }

    fun toPairingUri(includeTokens: Boolean = false): String {
        val q = linkedMapOf(
            "host" to host, "bridge" to "$bridgePort", "mgmt" to "$mgmtPort", "tls" to if (useTls) "1" else "0",
        )
        if (certPin.isNotEmpty()) q["pin"] = certPin
        if (includeTokens) {
            if (bridgeToken.isNotEmpty()) q["bridge_token"] = bridgeToken
            if (mgmtToken.isNotEmpty()) q["mgmt_token"] = mgmtToken
        }
        return "huanhermes://connect?" + q.entries.joinToString("&") { "${it.key}=${encode(it.value)}" }
    }

    override fun toString() =
        "HostConfig(host=$host, bridge=$bridgePort, mgmt=$mgmtPort, tls=$useTls, device=$deviceId)"

    companion object {
        fun newDeviceId(): String = UUID.randomUUID().toString().replace("-", "").take(12)
        fun validPort(port: Int) = port in 1..65535
        fun encode(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

        fun formatHost(raw: String): String {
            val h = raw.trim()
            if (h.startsWith("[") && h.endsWith("]")) return h
            return if (h.contains(':')) "[$h]" else h
        }

        /**
         * Parses `huanhermes://connect?host=&bridge=&mgmt=&tls=` (tokens optional).
         * Returns null for anything that is not a usable pairing link, including
         * ports outside 1–65535.
         */
        fun parsePairingUri(raw: String): HostConfig? {
            val s = raw.trim()
            if (s.isEmpty()) return null
            val query = when {
                s.startsWith("huanhermes:", ignoreCase = true) -> runCatching { URI(s).rawQuery }.getOrNull()
                    ?: s.substringAfter('?', "").ifEmpty { s.substringAfter('#', "") }
                s.contains("host=") && (s.contains("bridge=") || s.contains("mgmt=")) -> s.substringAfter('?')
                else -> return null
            } ?: return null
            val params = query.split('&').filter { it.isNotEmpty() }.associate {
                val k = it.substringBefore('=')
                val v = it.substringAfter('=', "")
                decode(k) to decode(v)
            }
            val host = (params["host"] ?: params["h"]).orEmpty().trim().removePrefix("[").removeSuffix("]")
            if (host.isEmpty()) return null
            val bridge = port(params["bridge"] ?: params["bridge_port"], 9810) ?: return null
            val mgmt = port(params["mgmt"] ?: params["mgmt_port"], 9820) ?: return null
            val tls = (params["tls"] ?: params["use_tls"] ?: "0").lowercase() in setOf("1", "true", "yes")
            return HostConfig(
                host = host, bridgePort = bridge, mgmtPort = mgmt, useTls = tls,
                bridgeToken = params["bridge_token"].orEmpty().trim(),
                mgmtToken = params["mgmt_token"].orEmpty().trim(),
                certPin = Pinning.normalize(params["pin"].orEmpty()),
            )
        }

        /** Query parameters of a pairing link (for `code` / `name`). */
        fun pairingParams(raw: String): Map<String, String> {
            val s = raw.trim()
            val query = s.substringAfter('?', "").ifEmpty { s.substringAfter('#', "") }
            return query.split('&').filter { it.isNotEmpty() }.associate { decode(it.substringBefore('=')) to decode(it.substringAfter('=', "")) }
        }

        private fun port(raw: String?, default: Int): Int? {
            if (raw.isNullOrBlank()) return default
            val n = raw.trim().toIntOrNull() ?: return null
            return n.takeIf { validPort(it) }
        }

        private fun decode(v: String) = runCatching { URLDecoder.decode(v, "UTF-8") }.getOrDefault(v)
    }
}
