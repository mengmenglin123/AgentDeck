package com.huanmeng.huanhermes

import android.app.Application
import com.huanmeng.huanhermes.data.SettingsRepository

/**
 * Nothing here may throw: an exception before the first frame leaves the user
 * stuck on the splash screen (the 0.1.204 bug). Everything is lazy.
 */
class HuanHermesApp : Application() {
    val settings: SettingsRepository by lazy { SettingsRepository(this) }
}
