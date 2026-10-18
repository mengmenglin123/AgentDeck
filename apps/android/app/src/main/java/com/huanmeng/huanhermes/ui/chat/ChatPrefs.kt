package com.huanmeng.huanhermes.ui.chat

import androidx.compose.runtime.staticCompositionLocalOf

/** Chat-related settings, provided once at the root so every chat surface reads the same values. */
data class ChatPrefs(
    val enterToSend: Boolean = false,
    val quickMessages: List<String> = emptyList(),
    val codeLineNumbers: Boolean = false,
    val codeWrap: Boolean = false,
    val confirmAllowAll: Boolean = true,
)

val LocalChatPrefs = staticCompositionLocalOf { ChatPrefs() }
