package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.ui.vm.SessionsViewModel

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SessionsScreen(vm: SessionsViewModel, onOpenHosts: () -> Unit, onOpenChat: (com.huanmeng.huanhermes.core.chat.SessionRef) -> Unit) {
    val state by vm.sessions.collectAsStateWithLifecycle()
    val active by vm.active.collectAsStateWithLifecycle()
    val projects by vm.projects.collectAsStateWithLifecycle()
    var creating by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<SessionInfo?>(null) }
    var deleting by remember { mutableStateOf<SessionInfo?>(null) }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("会话")
                        Text(
                            active?.name ?: "未连接 Host",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { vm.refresh() }, enabled = active != null) { Icon(Icons.Outlined.Refresh, "刷新") }
                    IconButton(onClick = onOpenHosts) { Icon(Icons.Outlined.Dns, "Host 连接") }
                },
            )
        },
        floatingActionButton = {
            if (active != null) FloatingActionButton(onClick = { creating = true }) { Icon(Icons.Outlined.Add, "新建会话") }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            state.error?.let {
                Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            when {
                active == null -> Empty("还没有连接 Host", "添加 Host 后即可查看和创建会话。") {
                    Button(onClick = onOpenHosts) { Text("添加 Host") }
                }
                state.sessions.isEmpty() && !state.loading -> Empty("暂无会话", "点右下角 + 新建一个。") {}
                else -> LazyColumn(
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.sessions, key = { it.id }) { s ->
                        var menu by remember { mutableStateOf(false) }
                        Box {
                            ElevatedCard(
                                Modifier.fillMaxWidth().combinedClickable(
                                    onClick = { onOpenChat(vm.remember(s)) },
                                    onLongClick = { menu = true },
                                    onLongClickLabel = "更多操作",
                                ),
                            ) {
                                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text(s.displayTitle, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(
                                            listOfNotNull(s.project.ifBlank { null }, s.model, if (s.running) "运行中" else null).joinToString(" · "),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                }
                            }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text("重命名") }, onClick = { menu = false; renaming = s })
                                DropdownMenuItem(text = { Text("删除") }, onClick = { menu = false; deleting = s })
                            }
                        }
                    }
                }
            }
        }
    }

    if (creating) {
        var title by remember { mutableStateOf("") }
        var project by remember(projects) { mutableStateOf(projects.firstOrNull()?.name ?: "") }
        AlertDialog(
            onDismissRequest = { creating = false },
            title = { Text("新建会话") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (projects.isNotEmpty()) {
                        Text("项目", style = MaterialTheme.typography.labelLarge)
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(projects, key = { it.name }) { p ->
                                FilterChip(selected = project == p.name, onClick = { project = p.name }, label = { Text(p.name, maxLines = 1) })
                            }
                        }
                    } else {
                        OutlinedTextField(project, { project = it }, label = { Text("项目") }, singleLine = true)
                    }
                    OutlinedTextField(title, { title = it }, label = { Text("标题（可选）") }, singleLine = true)
                }
            },
            confirmButton = {
                TextButton(enabled = project.isNotBlank(), onClick = {
                    creating = false
                    vm.create(project.trim(), title.trim().ifEmpty { null }) { onOpenChat(vm.remember(it)) }
                }) { Text("创建") }
            },
            dismissButton = { TextButton(onClick = { creating = false }) { Text("取消") } },
        )
    }

    renaming?.let { s ->
        var title by remember(s.id) { mutableStateOf(s.title ?: "") }
        AlertDialog(
            onDismissRequest = { renaming = null },
            title = { Text("重命名") },
            text = { OutlinedTextField(title, { title = it }, singleLine = true) },
            confirmButton = {
                TextButton(enabled = title.isNotBlank(), onClick = { vm.rename(s, title.trim()); renaming = null }) { Text("保存") }
            },
            dismissButton = { TextButton(onClick = { renaming = null }) { Text("取消") } },
        )
    }

    deleting?.let { s ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("删除「${s.displayTitle}」？") },
            text = { Text("会从 Host 删除这个会话。") },
            confirmButton = { TextButton(onClick = { vm.delete(s); deleting = null }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun Empty(title: String, body: String, action: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Outlined.Dns, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(12.dp))
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(4.dp))
        Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        action()
    }
}
