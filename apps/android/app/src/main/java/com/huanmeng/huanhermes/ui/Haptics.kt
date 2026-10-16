package com.huanmeng.huanhermes.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import com.huanmeng.huanhermes.ui.theme.LocalHaptics

/** Haptic ticks that respect the user's setting. */
class Haptic(private val enabled: Boolean, private val perform: (HapticFeedbackType) -> Unit) {
    fun tick() { if (enabled) perform(HapticFeedbackType.TextHandleMove) }
    fun confirm() { if (enabled) perform(HapticFeedbackType.LongPress) }
}

@Composable
fun rememberHaptic(): Haptic {
    val feedback = LocalHapticFeedback.current
    val enabled = LocalHaptics.current
    return remember(feedback, enabled) { Haptic(enabled) { feedback.performHapticFeedback(it) } }
}
