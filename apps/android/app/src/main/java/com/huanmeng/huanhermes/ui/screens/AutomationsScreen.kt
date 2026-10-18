package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.data.AppGraph
import com.huanmeng.huanhermes.notify.AutomationWorker
import kotlinx.coroutines.launch

/** Scheduled prompts (F5): list, pause, delete. New ones are set from a chat's ⋮ menu. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AutomationsScreen(graph: AppGraph, onBack: () -> Unit) {
    val list by graph.extras.automations.collectAsState(initial = emptyList())
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    fun edit(t: (List<com.huanmeng.huanhermes.core.overview.Automation>) -> List<com.huanmeng.huanhermes.core.overview.Automation>) =
        scope.launch { graph.extras.updateAutomations(t); AutomationWorker.schedule(ctx.applicationContext) }
    Scaffold(topBar = {
        TopAppBar(
            title = { Text("定时提示") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
        )
    }) { pad ->
        LazyColumn(Modifier.padding(pad).fillMaxSize().testTag("automations"), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (list.isEmpty()) item {
                Text("还没有定时提示。在任意会话右上角 ⋮ →「定时发送…」新建，比如每天 9:00 让 Agent 跑一遍测试。",
                    Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            items(list, key = { it.id }) { a ->
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(a.prompt, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text("${a.title} · ${a.scheduleLabel}" + (a.lastResult?.let { " · 上次：$it" } ?: ""),
                                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = a.enabled, onCheckedChange = { on -> edit { l -> l.map { if (it.id == a.id) it.copy(enabled = on) else it } } })
                        IconButton(onClick = { edit { l -> l.filterNot { it.id == a.id } } }) { Icon(Icons.Outlined.Delete, "删除") }
                    }
                }
            }
        }
    }
}
