package com.huanmeng.huanhermes.ui

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import com.huanmeng.huanhermes.ui.screens.InboxScreen
import com.huanmeng.huanhermes.ui.vm.InboxViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.huanmeng.huanhermes.HuanHermesApp
import com.huanmeng.huanhermes.core.chat.SessionRef
import com.huanmeng.huanhermes.data.AppSettings
import com.huanmeng.huanhermes.data.SettingsRepository
import com.huanmeng.huanhermes.ui.screens.ChatScreen
import com.huanmeng.huanhermes.ui.screens.HostsScreen
import com.huanmeng.huanhermes.ui.screens.SessionsScreen
import com.huanmeng.huanhermes.ui.screens.SettingsScreen
import com.huanmeng.huanhermes.ui.screens.ToolsScreen
import com.huanmeng.huanhermes.ui.vm.ChatViewModel
import com.huanmeng.huanhermes.ui.vm.HostsViewModel
import com.huanmeng.huanhermes.ui.vm.SessionsViewModel

private enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    Sessions("sessions", "会话", Icons.Outlined.ChatBubbleOutline),
    Inbox("inbox", "需要我", Icons.Outlined.PanTool),
    Tools("tools", "工具", Icons.Outlined.Apps),
    Settings("settings", "设置", Icons.Outlined.Settings),
}

@Composable
fun HuanHermesRoot(settings: AppSettings, repo: SettingsRepository) {
    val graph = (LocalContext.current.applicationContext as HuanHermesApp).graph
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val current = entry?.destination?.route
    val showBar = Tab.entries.any { it.route == current }
    val sessionsVm: SessionsViewModel = viewModel { SessionsViewModel(graph) }
    val inboxVm: InboxViewModel = viewModel { InboxViewModel(graph) }
    val inbox by inboxVm.state.collectAsStateWithLifecycle()
    val pending = inbox.visible.size
    androidx.compose.runtime.LaunchedEffect(current) {
        if (current == Tab.Sessions.route || current == Tab.Inbox.route) inboxVm.refresh()
    }
    val openChat = { ref: SessionRef ->
        val e = { v: String? -> android.net.Uri.encode(v.orEmpty()) }
        nav.navigate("chat/${e(ref.id)}?sk=${e(ref.sessionKey)}&p=${e(ref.project)}&t=${e(ref.title)}")
    }
    // Each screen handles its own top/bottom insets; the outer Scaffold only reserves the nav bar.
    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showBar) NavigationBar {
                Tab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = current == tab.route,
                        onClick = {
                            nav.navigate(tab.route) {
                                popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            if (tab == Tab.Inbox && pending > 0) BadgedBox(badge = { Badge { Text(if (pending > 99) "99+" else "$pending") } }) {
                                Icon(tab.icon, contentDescription = "$pending 项待处理")
                            } else Icon(tab.icon, contentDescription = null)
                        },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = Tab.Sessions.route, modifier = Modifier.padding(padding)) {
            composable(Tab.Sessions.route) {
                SessionsScreen(
                    sessionsVm,
                    onOpenHosts = { nav.navigate("hosts") },
                    onOpenChat = openChat,
                )
            }
            composable(Tab.Inbox.route) {
                InboxScreen(inboxVm, onOpenChat = openChat, onOpenHosts = { nav.navigate("hosts") })
            }
            composable(Tab.Tools.route) { ToolsScreen(onOpenHosts = { nav.navigate("hosts") }, onOpenInbox = { nav.navigate(Tab.Inbox.route) { launchSingleTop = true } }) }
            composable(Tab.Settings.route) { SettingsScreen(settings, repo, onOpenHosts = { nav.navigate("hosts") }) }
            composable("hosts") {
                val vm: HostsViewModel = viewModel { HostsViewModel(graph) }
                HostsScreen(vm, onBack = { nav.popBackStack() }, onConnected = { nav.popBackStack() })
            }
            composable(
                "chat/{id}?sk={sk}&p={p}&t={t}",
                arguments = listOf(
                    navArgument("id") { type = NavType.StringType },
                    navArgument("sk") { type = NavType.StringType; defaultValue = "" },
                    navArgument("p") { type = NavType.StringType; defaultValue = "" },
                    navArgument("t") { type = NavType.StringType; defaultValue = "" },
                ),
            ) { backStack ->
                val args = backStack.arguments
                val id = args?.getString("id").orEmpty()
                val sk = args?.getString("sk").orEmpty()
                val fallback = if (sk.isEmpty()) null else SessionRef(
                    id, sk, args?.getString("p")?.ifEmpty { null }, args?.getString("t")?.ifEmpty { null } ?: "会话",
                )
                val vm: ChatViewModel = viewModel(key = "chat-$id") { ChatViewModel(graph, id, fallback) }
                ChatScreen(vm, onBack = { nav.popBackStack() }, foldTurns = settings.foldTurns)
            }
        }
    }
}
