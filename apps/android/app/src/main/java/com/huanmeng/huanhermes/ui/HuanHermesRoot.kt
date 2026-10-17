package com.huanmeng.huanhermes.ui

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.unit.dp
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
    // Tablets and unfolded foldables (>= 840dp): list and chat side by side.
    val wide = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp >= 840
    var paneRef by androidx.compose.runtime.saveable.rememberSaveable(stateSaver = SessionRefSaver) {
        androidx.compose.runtime.mutableStateOf<SessionRef?>(null)
    }
    val openChat = { ref: SessionRef ->
        if (wide) {
            paneRef = ref
            if (current != Tab.Sessions.route) nav.navigate(Tab.Sessions.route) {
                popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                launchSingleTop = true
                restoreState = true
            }
        } else {
            val e = { v: String? -> android.net.Uri.encode(v.orEmpty()) }
            nav.navigate("chat/${e(ref.id)}?sk=${e(ref.sessionKey)}&p=${e(ref.project)}&t=${e(ref.title)}")
        }
    }
    // A tapped approval notification opens "需要我".
    val openTab by graph.openTabRequests.collectAsStateWithLifecycle()
    androidx.compose.runtime.LaunchedEffect(openTab) {
        if (openTab == "inbox") {
            nav.navigate(Tab.Inbox.route) {
                popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                launchSingleTop = true
            }
            graph.openTabRequests.value = null
        }
    }
    NotificationPermissionOnce(settings, repo, hasHosts = sessionsVm.profiles.collectAsStateWithLifecycle().value.profiles.isNotEmpty())
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
                if (!wide) SessionsScreen(
                    sessionsVm,
                    onOpenHosts = { nav.navigate("hosts") },
                    onOpenChat = openChat,
                ) else androidx.compose.foundation.layout.Row(Modifier.fillMaxSize()) {
                    androidx.compose.foundation.layout.Box(Modifier.weight(0.38f).fillMaxHeight()) {
                        SessionsScreen(sessionsVm, onOpenHosts = { nav.navigate("hosts") }, onOpenChat = openChat, selectedId = paneRef?.id)
                    }
                    androidx.compose.material3.VerticalDivider()
                    androidx.compose.foundation.layout.Box(Modifier.weight(0.62f).fillMaxHeight()) {
                        val ref = paneRef
                        if (ref == null) ChatPanePlaceholder() else androidx.compose.runtime.key(ref.id) {
                            ScopedViewModels {
                                graph.sessionRefs.putIfAbsent(ref.id, ref)
                                val vm: ChatViewModel = viewModel { ChatViewModel(graph, ref.id, ref) }
                                ChatScreen(vm, onBack = { paneRef = null }, foldTurns = settings.foldTurns)
                            }
                        }
                    }
                }
            }
            composable(Tab.Inbox.route) {
                InboxScreen(inboxVm, onOpenChat = openChat, onOpenHosts = { nav.navigate("hosts") })
            }
            composable(Tab.Tools.route) {
                ToolsScreen(
                    onOpenHosts = { nav.navigate("hosts") },
                    onOpenInbox = { nav.navigate(Tab.Inbox.route) { launchSingleTop = true } },
                    onOpen = { route -> nav.navigate(route) },
                )
            }
            composable("status") {
                val vm: com.huanmeng.huanhermes.ui.vm.DashboardViewModel = viewModel { com.huanmeng.huanhermes.ui.vm.DashboardViewModel(graph) }
                com.huanmeng.huanhermes.ui.screens.DashboardScreen(vm, statusOnly = true, onBack = { nav.popBackStack() }, onOpenInbox = { nav.navigate(Tab.Inbox.route) { launchSingleTop = true } })
            }
            composable("dashboard") {
                val vm: com.huanmeng.huanhermes.ui.vm.DashboardViewModel = viewModel { com.huanmeng.huanhermes.ui.vm.DashboardViewModel(graph) }
                com.huanmeng.huanhermes.ui.screens.DashboardScreen(vm, statusOnly = false, onBack = { nav.popBackStack() }, onOpenInbox = { nav.navigate(Tab.Inbox.route) { launchSingleTop = true } })
            }
            composable("workspace") {
                val vm: com.huanmeng.huanhermes.ui.vm.WorkspaceViewModel = viewModel { com.huanmeng.huanhermes.ui.vm.WorkspaceViewModel(graph) }
                com.huanmeng.huanhermes.ui.screens.WorkspaceScreen(vm, onBack = { nav.popBackStack() })
            }
            composable("git") {
                val vm: com.huanmeng.huanhermes.ui.vm.GitViewModel = viewModel { com.huanmeng.huanhermes.ui.vm.GitViewModel(graph) }
                com.huanmeng.huanhermes.ui.screens.GitScreen(vm, onBack = { nav.popBackStack() })
            }
            composable("terminal") {
                val vm: com.huanmeng.huanhermes.ui.vm.TerminalViewModel = viewModel { com.huanmeng.huanhermes.ui.vm.TerminalViewModel(graph) }
                com.huanmeng.huanhermes.ui.screens.TerminalScreen(vm, onBack = { nav.popBackStack() })
            }
            composable("catalog/{kind}") { e ->
                val kind = runCatching { com.huanmeng.huanhermes.core.catalog.CatalogKind.valueOf(e.arguments?.getString("kind").orEmpty()) }
                    .getOrDefault(com.huanmeng.huanhermes.core.catalog.CatalogKind.AGENTS)
                val vm: com.huanmeng.huanhermes.ui.vm.CatalogViewModel = viewModel(key = "catalog-$kind") { com.huanmeng.huanhermes.ui.vm.CatalogViewModel(graph, kind) }
                com.huanmeng.huanhermes.ui.screens.CatalogScreen(vm, onBack = { nav.popBackStack() })
            }
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

private val SessionRefSaver = androidx.compose.runtime.saveable.listSaver<SessionRef?, String>(
    save = { r -> if (r == null) emptyList() else listOf(r.id, r.sessionKey, r.project.orEmpty(), r.title) },
    restore = { l -> if (l.size < 4) null else SessionRef(l[0], l[1], l[2].ifEmpty { null }, l[3]) },
)

/** ViewModels that live exactly as long as this piece of UI (the tablet chat pane). */
@Composable
private fun ScopedViewModels(content: @Composable () -> Unit) {
    val owner = androidx.compose.runtime.remember {
        object : androidx.lifecycle.ViewModelStoreOwner {
            override val viewModelStore = androidx.lifecycle.ViewModelStore()
        }
    }
    androidx.compose.runtime.DisposableEffect(owner) { onDispose { owner.viewModelStore.clear() } }
    androidx.compose.runtime.CompositionLocalProvider(androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner provides owner) {
        content()
    }
}

@Composable
private fun ChatPanePlaceholder() {
    androidx.compose.foundation.layout.Column(
        Modifier.fillMaxSize(),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
        horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Outlined.ChatBubbleOutline, null, Modifier.padding(8.dp).then(Modifier), tint = androidx.compose.material3.MaterialTheme.colorScheme.primary)
        Text("选择左侧的会话", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)
        Text("或在下方输入第一句话开始新会话", style = androidx.compose.material3.MaterialTheme.typography.bodyMedium, color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Asks for the notification permission once, after the user has added a Host (Android 13+). */
@Composable
private fun NotificationPermissionOnce(settings: AppSettings, repo: SettingsRepository, hasHosts: Boolean) {
    if (android.os.Build.VERSION.SDK_INT < 33) return
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val launcher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { }
    androidx.compose.runtime.LaunchedEffect(hasHosts, settings.askedNotificationPermission, settings.approvalNotifications) {
        if (!hasHosts || settings.askedNotificationPermission || !settings.approvalNotifications) return@LaunchedEffect
        val granted = androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        repo.update { it.copy(askedNotificationPermission = true) }
        if (!granted) runCatching { launcher.launch(android.Manifest.permission.POST_NOTIFICATIONS) }
    }
}
