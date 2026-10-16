package com.huanmeng.huanhermes

import android.graphics.Color
import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import com.huanmeng.huanhermes.data.ThemeMode
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.data.AppSettings
import com.huanmeng.huanhermes.ui.HuanHermesRoot
import com.huanmeng.huanhermes.ui.theme.HuanHermesTheme

class MainActivity : ComponentActivity() {
    override fun onStart() {
        super.onStart()
        (application as HuanHermesApp).graph.onForeground()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val repo = (application as HuanHermesApp).settings
        setContent {
            val settings by repo.settings.collectAsStateWithLifecycle(initialValue = AppSettings())
            val systemDark = isSystemInDarkTheme()
            val dark = when (settings.themeMode) {
                ThemeMode.SYSTEM -> systemDark
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }
            // System bar icons follow the app's theme, not the system's (forced dark
            // on a light system left dark icons on a dark background).
            DisposableEffect(dark) {
                val style = if (dark) SystemBarStyle.dark(Color.TRANSPARENT)
                    else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
                onDispose {}
            }
            HuanHermesTheme(settings) {
                HuanHermesRoot(settings = settings, repo = repo)
            }
        }
    }
}
