package com.huanmeng.huanhermes.ui.screens

import com.huanmeng.huanhermes.ui.components.AppCard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.chat.SessionRef
import com.huanmeng.huanhermes.core.overview.InboxItem
import com.huanmeng.huanhermes.ui.chat.PermissionButtons
import com.huanmeng.huanhermes.ui.rememberHaptic
import com.huanmeng.huanhermes.ui.theme.Brand
import com.huanmeng.huanhermes.ui.vm.InboxViewModel

/** "需要我": every pending approval on every Host, answerable in place. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InboxScreen(vm: InboxViewModel, onOpenChat: (SessionRef) -> Unit, onOpenHosts: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    val busy by vm.busy.collectAsStateWithLifecycle()
    val error by vm.error.collectAsStateWithLifecycle()
    val haptic = rememberHaptic()
    val chatPrefs = com.huanmeng.huanhermes.ui.chat.LocalChatPrefs.current
    val deviceAuth = com.huanmeng.huanhermes.ui.rememberDeviceAuth()
    LaunchedEffect(Unit) { vm.refresh() }
    // Only a pull shows the indicator; background refreshes stay quiet.
    var pulling by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    LaunchedEffect(state.loading) { if (!state.loading) pulling = false }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(title = {
                Column {
                    Text("需要我")
                    val n = state.visible.size
                    Text(
                        if (n == 0) "没有待处理的事项" else "$n 项等待你处理",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            })
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = pulling,
            onRefresh = { pulling = true; vm.refresh() },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            LazyColumn(
                Modifier.fillMaxSize().testTag("inbox-list"),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                error?.let { e ->
                    item(key = "error") { Text(e, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                }
                if (state.hosts.isEmpty() && !state.loading) item(key = "no-hosts") {
                    Empty(Icons.Outlined.Dns, "还没有 Host", "添加 Host 后，所有需要你批准的操作会集中在这里。") {
                        Button(onClick = onOpenHosts) { Text("添加 Host") }
                    }
                } else if (state.visible.isEmpty() && !state.loading) item(key = "empty") {
                    Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Outlined.TaskAlt, null, Modifier.size(48.dp), tint = Brand.success)
                        Spacer(Modifier.size(12.dp))
                        Text("都处理完了", style = MaterialTheme.typography.titleMedium)
                        Text("Agent 需要你批准时会出现在这里，下拉可刷新。", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                items(state.visible, key = { it.key }) { item ->
                    InboxCard(
                        item = item,
                        sending = busy == item.key,
                        onDecision = { d ->
                            if (d == "allow_all" && chatPrefs.confirmAllowAll) deviceAuth("确认允许本会话内的同类操作") { haptic.confirm(); vm.decide(item, d) }
                            else { haptic.confirm(); vm.decide(item, d) }
                        },
                        onOpen = { vm.open(item, onOpenChat) },
                        modifier = Modifier.animateItem(),
                    )
                }
                val problems = state.hosts.filter { it.error != null }
                if (problems.isNotEmpty() || state.unsupportedHosts.isNotEmpty()) item(key = "hosts-footer") {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        problems.forEach { h ->
                            HostNote(Icons.Outlined.CloudOff, "${h.hostName}：连不上（${h.error}）")
                        }
                        state.unsupportedHosts.forEach { h ->
                            HostNote(Icons.Outlined.Info, "${h.hostName}：Host companion 版本较旧，升级后才能在这里集中审批；打开会话仍可审批。")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HostNote(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(6.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun InboxCard(item: InboxItem, sending: Boolean, onDecision: (String) -> Unit, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    AppCard(modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.clickable(onClickLabel = "打开会话", onClick = onOpen), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.PanTool, null, Modifier.size(18.dp), tint = Brand.warning)
                Spacer(Modifier.width(8.dp))
                Column(Modifier.weight(1f)) {
                    Text(item.session.displayTitle, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        listOf(item.hostName, item.session.project).filter { it.isNotBlank() }.joinToString(" · "),
                        style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = onOpen) { Text("打开") }
            }
            Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.small) {
                Text(
                    item.permission.prompt.ifBlank { "Agent 请求权限" },
                    Modifier.fillMaxWidth().padding(10.dp),
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    maxLines = 8, overflow = TextOverflow.Ellipsis,
                )
            }
            if (sending) Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text("发送中…", style = MaterialTheme.typography.bodySmall)
            } else {
                val data = item.permission.buttons.map { it.data }
                // Plans and questions need the full card: answer them in the session.
                if (data.isNotEmpty() && data.none { d -> listOf("allow", "allow_all", "deny").any { d.endsWith(":$it") } }) {
                    androidx.compose.material3.Button(onClick = onOpen) { Text("打开会话处理") }
                } else PermissionButtons(data, onDecision)
            }
        }
    }
}
