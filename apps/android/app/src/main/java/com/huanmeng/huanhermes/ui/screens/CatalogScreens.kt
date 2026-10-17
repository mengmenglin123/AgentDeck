package com.huanmeng.huanhermes.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.catalog.CatalogEntry
import com.huanmeng.huanhermes.core.catalog.CatalogKind
import com.huanmeng.huanhermes.core.overview.SessionOverview
import com.huanmeng.huanhermes.ui.vm.CatalogViewModel
import com.huanmeng.huanhermes.ui.vm.DashboardViewModel

@Composable
fun levelColor(level: String?): Color = when (level) {
    "ok" -> Color(0xFF2E9D5B)
    "warn", "warning" -> Color(0xFFE0A100)
    "error" -> MaterialTheme.colorScheme.error
    "off" -> MaterialTheme.colorScheme.outline
    "debug" -> MaterialTheme.colorScheme.outlineVariant
    else -> MaterialTheme.colorScheme.primary
}

private val kindHint = mapOf(
    CatalogKind.AGENTS to "这个 Host 上可用的 Agent 和平台",
    CatalogKind.SKILLS to "Agent 可以调用的技能",
    CatalogKind.MCP to "已配置的 MCP 服务器",
    CatalogKind.TOOLS to "来自 MCP 服务器的全部工具",
    CatalogKind.MEMORY to "Agent 的长期记忆（只读）",
    CatalogKind.CRON to "定时任务（只读）",
    CatalogKind.ACTIVITY to "最近的运行、权限与错误",
    CatalogKind.LOGS to "Host 最近的日志（已脱敏）",
    CatalogKind.AUDIT to "每一次允许/拒绝都会记在这里",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogScreen(vm: CatalogViewModel, onBack: () -> Unit) {
    val st by vm.state.collectAsStateWithLifecycle()
    val rows by vm.visible.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()
    val level by vm.level.collectAsStateWithLifecycle()
    val kind = vm.kind
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(kind.title)
                        if (st.hostName.isNotEmpty()) Text(st.hostName, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = { IconButton(onClick = { vm.refresh() }) { Icon(Icons.Outlined.Refresh, "刷新") } },
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().testTag("catalog-${kind.name.lowercase()}")) {
            if (st.loading) LinearProgressIndicator(Modifier.fillMaxWidth()) else Spacer(Modifier.height(4.dp))
            if (kind.projectScoped && st.projects.size > 1) {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = st.project == null, onClick = { vm.selectProject(null) }, label = { Text("默认") })
                    st.projects.forEach { p -> FilterChip(selected = st.project == p.name, onClick = { vm.selectProject(p.name) }, label = { Text(p.name) }) }
                }
            }
            if (kind == CatalogKind.LOGS) {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("" to "全部", "error" to "错误", "warn" to "警告", "info" to "信息").forEach { (v, label) ->
                        FilterChip(selected = level == v, onClick = { vm.level.value = v }, label = { Text(label) })
                    }
                }
            }
            if (kind.searchable && st.entries.isNotEmpty()) {
                OutlinedTextField(
                    value = query, onValueChange = { vm.query.value = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                    singleLine = true, placeholder = { Text("搜索 ${kind.title}") },
                    leadingIcon = { Icon(Icons.Outlined.Search, null) },
                    shape = RoundedCornerShape(24.dp),
                )
            }
            when {
                st.unsupported -> EmptyState(Icons.Outlined.CloudOff, "这个 Host 还不支持 ${kind.title}", "升级 Host companion 后就能看到")
                st.error != null && st.entries.isEmpty() -> EmptyState(Icons.Outlined.CloudOff, "加载失败", st.error.orEmpty())
                !st.loading && rows.isEmpty() -> EmptyState(Icons.Outlined.Inbox, if (query.isNotBlank() || level.isNotEmpty()) "没有匹配的结果" else "暂无内容", kindHint[kind].orEmpty())
                else -> LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item(key = "hint") {
                        Text("${rows.size} 项 · ${kindHint[kind].orEmpty()}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(4.dp))
                    }
                    items(rows, key = { it.id }) { CatalogRow(it, mono = kind == CatalogKind.LOGS) }
                    item { Spacer(Modifier.navigationBarsPadding()) }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CatalogRow(e: CatalogEntry, mono: Boolean) {
    var open by rememberSaveable(e.id) { mutableStateOf(false) }
    val expandable = e.body.isNotBlank() && e.body != e.subtitle || e.details.isNotEmpty() || e.subtitle.length > 80 || e.title.length > 80
    val now = System.currentTimeMillis() / 1000.0
    Card(
        Modifier.fillMaxWidth().animateContentSize().clickable(enabled = expandable) { open = !open },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (e.level != null) {
                    Box(Modifier.size(8.dp).background(levelColor(e.level), CircleShape))
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    e.title, Modifier.weight(1f),
                    style = if (mono) MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace) else MaterialTheme.typography.titleSmall,
                    maxLines = if (open) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
                )
                e.ts?.takeIf { it > 0 }?.let {
                    Text(SessionOverview.relativeTime(it, now), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 8.dp))
                }
            }
            if (e.subtitle.isNotBlank()) {
                Text(e.subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = if (open) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
            }
            if (e.chips.isNotEmpty()) {
                FlowRow(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    e.chips.take(if (open) 40 else 6).forEach { Pill(it) }
                }
            }
            if (open && e.body.isNotBlank() && e.body != e.subtitle) {
                Surface(Modifier.fillMaxWidth().padding(top = 8.dp), shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest) {
                    Text(e.body, Modifier.padding(10.dp), style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
                }
            }
            if (open) e.details.forEach { (k, v) ->
                val shown = v.toDoubleOrNull()?.let { SessionOverview.relativeTime(it, now) } ?: v
                Row(Modifier.padding(top = 4.dp)) {
                    Text(k, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(72.dp))
                    Text(shown, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

@Composable
fun Pill(text: String) {
    Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.secondaryContainer) {
        Text(text, Modifier.padding(horizontal = 8.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSecondaryContainer, maxLines = 1)
    }
}

@Composable
private fun EmptyState(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, body: String) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.outline)
        Text(title, Modifier.padding(top = 12.dp), style = MaterialTheme.typography.titleMedium)
        if (body.isNotBlank()) Text(body, Modifier.padding(top = 4.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Status (compact = false) and Dashboard share one screen; Dashboard leads with the numbers. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DashboardScreen(vm: DashboardViewModel, statusOnly: Boolean, onBack: () -> Unit, onOpenInbox: () -> Unit) {
    val st by vm.state.collectAsStateWithLifecycle()
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(if (statusOnly) "Status" else "Dashboard")
                        if (st.hostName.isNotEmpty()) Text(st.hostName, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = { IconButton(onClick = { vm.refresh() }) { Icon(Icons.Outlined.Refresh, "刷新") } },
            )
        },
    ) { pad ->
        LazyColumn(
            Modifier.padding(pad).fillMaxSize().testTag(if (statusOnly) "status-screen" else "dashboard-screen"),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (st.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            st.error?.let { err -> item { Text(err, color = MaterialTheme.colorScheme.error) } }
            if (!statusOnly) {
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        StatTile("会话", st.sessions.size.toString(), Modifier.weight(1f))
                        StatTile("运行中", st.running.toString(), Modifier.weight(1f), accent = if (st.running > 0) levelColor("ok") else null)
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        StatTile("需要我", st.pendingAllHosts.toString(), Modifier.weight(1f).clickable(onClick = onOpenInbox), accent = if (st.pendingAllHosts > 0) levelColor("warn") else null)
                        StatTile("项目", st.projects.size.toString(), Modifier.weight(1f))
                    }
                }
                if (st.byProject.isNotEmpty()) item {
                    SectionCard("按项目") {
                        val max = st.byProject.maxOf { it.second }.coerceAtLeast(1)
                        st.byProject.forEach { (name, n) ->
                            Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(name, Modifier.width(96.dp), style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Box(Modifier.weight(1f).height(10.dp).background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(5.dp))) {
                                    Box(Modifier.fillMaxWidth(n / max.toFloat()).height(10.dp).background(MaterialTheme.colorScheme.primary, RoundedCornerShape(5.dp)))
                                }
                                Text(n.toString(), Modifier.padding(start = 8.dp), style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
                }
            }
            if (st.statusRows.isNotEmpty()) item {
                SectionCard("Host") {
                    st.statusRows.forEach { (k, v) ->
                        Row(Modifier.padding(vertical = 4.dp)) {
                            Text(k, Modifier.width(88.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(v, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
            if (st.capabilities.isNotEmpty()) item {
                SectionCard("能力（${st.capabilities.size}）") {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        st.capabilities.forEach { Pill(it) }
                    }
                }
            }
            if (!statusOnly && st.hostCount > 1) item {
                Text("共 ${st.hostCount} 个 Host；“需要我”统计全部 Host。", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun StatTile(label: String, value: String, modifier: Modifier = Modifier, accent: Color? = null) {
    Card(modifier, shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
        Column(Modifier.padding(16.dp)) {
            Text(value, style = MaterialTheme.typography.headlineMedium, color = accent ?: MaterialTheme.colorScheme.onSurface)
            Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(bottom = 8.dp))
            content()
        }
    }
}
