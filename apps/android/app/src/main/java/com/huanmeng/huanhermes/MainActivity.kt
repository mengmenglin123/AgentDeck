package com.huanmeng.huanhermes

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

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

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) (application as HuanHermesApp).graph.onBackground()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        handleOpenTab(intent)
    }

    private fun handleOpenTab(intent: android.content.Intent?) {
        val tab = intent?.getStringExtra(com.huanmeng.huanhermes.notify.ApprovalNotifications.EXTRA_OPEN_TAB) ?: return
        (application as HuanHermesApp).graph.openTabRequests.value = tab
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val repo = (application as HuanHermesApp).settings
        handleOpenTab(intent)
        // Notifications start after the first frame; nothing here may block or throw.
        window.decorView.post {
            val app = application as HuanHermesApp
            app.graph.startNotifier(repo.settings.map { it.approvalNotifications })
            app.graph.scope.launch {
                val on = runCatching { repo.settings.first().approvalNotifications }.getOrDefault(true)
                com.huanmeng.huanhermes.notify.InboxWorker.schedule(applicationContext, on)
                val s = runCatching { repo.settings.first() }.getOrNull()
                // Re-announce the push endpoint (new Hosts, Host restarts) and resume keep-alive.
                s?.pushEndpoint?.let { app.graph.syncPush(it) }
                if (s?.keepAlive == true && on) com.huanmeng.huanhermes.notify.KeepAliveService.set(applicationContext, true)
            }
        }
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
