package com.huanmeng.huanhermes.core.net

/**
 * Removes credentials from any text that may reach logs, UI or notifications.
 * Covers `?token=` / `&token=` query values, `Bearer …` headers and any
 * secret value registered by the caller (raw or URL-encoded).
 */
object Redactor {
    private val queryToken = Regex("""([?&](?:token|bridge_token|mgmt_token|access_token)=)[^&#\s"'<>]*""", RegexOption.IGNORE_CASE)
    private val bearer = Regex("""(Bearer\s+)[A-Za-z0-9._~+/=\-]+""", RegexOption.IGNORE_CASE)
    const val MASK = "***"

    fun redact(text: String?, secrets: Collection<String> = emptyList()): String {
        if (text.isNullOrEmpty()) return text.orEmpty()
        var out: String = text
        for (secret in secrets) {
            if (secret.length < 4) continue
            out = out.replace(secret, MASK)
            for (encoded in setOf(java.net.URLEncoder.encode(secret, "UTF-8"), HostConfig.encode(secret))) {
                if (encoded != secret) out = out.replace(encoded, MASK)
            }
        }
        out = queryToken.replace(out) { it.groupValues[1] + MASK }
        out = bearer.replace(out) { it.groupValues[1] + MASK }
        return out
    }

    fun redact(error: Throwable, secrets: Collection<String> = emptyList()): String {
        val message = error.message?.takeIf { it.isNotBlank() } ?: error::class.java.simpleName
        return redact(message, secrets)
    }
}
