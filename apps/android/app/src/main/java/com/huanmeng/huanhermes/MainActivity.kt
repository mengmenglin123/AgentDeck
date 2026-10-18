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
        val graph = (application as HuanHermesApp).graph
        if (intent?.action == android.content.Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            val text = listOfNotNull(
                intent.getStringExtra(android.content.Intent.EXTRA_SUBJECT),
                intent.getStringExtra(android.content.Intent.EXTRA_TEXT),
            ).filter { it.isNotBlank() }.distinct().joinToString("\n")
            if (text.isNotBlank()) graph.pendingShare.value = text.take(20_000)
            return
        }
        intent?.getStringExtra(com.huanmeng.huanhermes.ui.Shortcuts.EXTRA_SESSION)?.let { id ->
            val sk = intent.getStringExtra(com.huanmeng.huanhermes.ui.Shortcuts.EXTRA_KEY) ?: return@let
            graph.openSessionRequests.value = com.huanmeng.huanhermes.core.chat.SessionRef(
                id, sk, intent.getStringExtra(com.huanmeng.huanhermes.ui.Shortcuts.EXTRA_PROJECT)?.ifEmpty { null },
                intent.getStringExtra(com.huanmeng.huanhermes.ui.Shortcuts.EXTRA_TITLE) ?: "会话",
            )
            return
        }
        val tab = intent?.getStringExtra(com.huanmeng.huanhermes.notify.ApprovalNotifications.EXTRA_OPEN_TAB) ?: return
        graph.openTabRequests.value = tab
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
                com.huanmeng.huanhermes.notify.AutomationWorker.schedule(applicationContext)
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
            androidx.compose.runtime.LaunchedEffect(settings.keepScreenOn) {
                if (settings.keepScreenOn) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            HuanHermesTheme(settings) {
                HuanHermesRoot(settings = settings, repo = repo)
            }
        }
    }
}
