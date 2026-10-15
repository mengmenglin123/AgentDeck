package com.huanmeng.huanhermes.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.huanmeng.huanhermes.data.AppSettings
import com.huanmeng.huanhermes.data.SettingsRepository
import com.huanmeng.huanhermes.ui.screens.SessionsScreen
import com.huanmeng.huanhermes.ui.screens.SettingsScreen
import com.huanmeng.huanhermes.ui.screens.ToolsScreen

private enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    Sessions("sessions", "会话", Icons.Outlined.ChatBubbleOutline),
    Tools("tools", "工具", Icons.Outlined.Apps),
    Settings("settings", "设置", Icons.Outlined.Settings),
}

@Composable
fun HuanHermesRoot(settings: AppSettings, repo: SettingsRepository) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val current = entry?.destination?.route
    Scaffold(
        bottomBar = {
            NavigationBar {
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
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = Tab.Sessions.route, modifier = Modifier.padding(padding)) {
            composable(Tab.Sessions.route) { SessionsScreen() }
            composable(Tab.Tools.route) { ToolsScreen() }
            composable(Tab.Settings.route) { SettingsScreen(settings, repo) }
        }
    }
}
