package com.huanmeng.huanhermes.core.chat

/** `@path` mentions in the composer. */
object Mentions {
    /**
     * The partial path after the last `@` when the text ends inside a mention
     * (`看看 @src/Ma` -> `src/Ma`). The `@` must start the text or follow
     * whitespace, so e-mail addresses never open the picker.
     */
    fun activeQuery(text: String): String? {
        val at = text.lastIndexOf('@')
        if (at < 0) return null
        if (at > 0 && !text[at - 1].isWhitespace()) return null
        val token = text.substring(at + 1)
        if (token.any { it.isWhitespace() } || token.length > 200) return null
        return token
    }

    /** Replaces the active mention with `@path ` (paths with spaces are quoted). */
    fun insert(text: String, path: String): String {
        val at = text.lastIndexOf('@')
        if (at < 0 || activeQuery(text) == null) return text
        val ref = if (path.any { it.isWhitespace() }) "\"$path\"" else path
        return text.substring(0, at) + "@" + ref + " "
    }
}
