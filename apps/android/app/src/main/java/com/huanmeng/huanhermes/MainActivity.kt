package com.huanmeng.huanhermes

import android.os.Bundle
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
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val repo = (application as HuanHermesApp).settings
        setContent {
            val settings by repo.settings.collectAsStateWithLifecycle(initialValue = AppSettings())
            HuanHermesTheme(settings) {
                HuanHermesRoot(settings = settings, repo = repo)
            }
        }
    }
}
