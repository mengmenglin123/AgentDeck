package com.huanmeng.huanhermes.ui

import android.app.Activity
import android.app.KeyguardManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext

/**
 * Asks for the device's own lock (fingerprint / face / PIN) before [onOk].
 * Devices without a screen lock pass straight through, so nothing ever blocks forever.
 */
@Composable
fun rememberDeviceAuth(): (reason: String, onOk: () -> Unit) -> Unit {
    val ctx = LocalContext.current
    val pending = remember { arrayOfNulls<() -> Unit>(1) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val ok = pending[0]
        pending[0] = null
        if (r.resultCode == Activity.RESULT_OK) ok?.invoke()
    }
    return remember(launcher) {
        { reason, onOk ->
            val km = ctx.getSystemService(KeyguardManager::class.java)
            @Suppress("DEPRECATION")
            val intent = if (km != null && km.isDeviceSecure) km.createConfirmDeviceCredentialIntent("AgentDeck", reason) else null
            if (intent == null) onOk() else {
                pending[0] = onOk
                runCatching { launcher.launch(intent) }.onFailure { pending[0] = null; onOk() }
            }
        }
    }
}
