package com.huanmeng.huanhermes.ui.screens

import androidx.compose.ui.draw.clip
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.ui.graphics.Shape
import com.huanmeng.huanhermes.ui.components.Design
import com.huanmeng.huanhermes.ui.components.Tag
import com.huanmeng.huanhermes.ui.components.Tint
import com.huanmeng.huanhermes.ui.components.groupShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.DoneAll
import androidx.compose.material.icons.outlined.FiberManualRecord
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Unarchive
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.chat.SessionRef
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.overview.SessionOverview
import com.huanmeng.huanhermes.core.overview.SessionRow
import com.huanmeng.huanhermes.core.overview.SessionStatus
import com.huanmeng.huanhermes.ui.rememberHaptic
import com.huanmeng.huanhermes.ui.theme.Brand
import com.huanmeng.huanhermes.ui.vm.SessionsViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SessionsScreen(vm: SessionsViewModel, onOpenHosts: () -> Unit, onOpenChat: (SessionRef) -> Unit, selectedId: String? = null) {
    val state by vm.sessions.collectAsStateWithLifecycle()
    val active by vm.active.collectAsStateWithLifecycle()
    val profiles by vm.profiles.collectAsStateWithLifecycle()
    val projects by vm.projects.collectAsStateWithLifecycle()
    val groups by vm.groups.collectAsStateWithLifecycle()
    val prefs by vm.prefs.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()
    val showArchived by vm.showArchived.collectAsStateWithLifecycle()
    val archivedCount by vm.archivedCount.collectAsStateWithLifecycle()
    var creating by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<SessionInfo?>(null) }
    var deleting by remember { mutableStateOf<SessionInfo?>(null) }
    var searching by rememberSaveable { mutableStateOf(false) }
    var hostMenu by remember { mutableStateOf(false) }
    var pulling by remember { mutableStateOf(false) }
    LaunchedEffect(state.loading) { if (!state.loading) pulling = false }
    val haptic = rememberHaptic()
    // Relative times tick once a minute.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(60_000); now = System.currentTimeMillis() } }
    // Coming back to the list (and every 20 s while it is open) picks up new statuses.
    LaunchedEffect(active?.id) { if (active != null) while (true) { vm.refresh(); delay(20_000) } }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(
                title = {
                    Box {
                        Column(
                            Modifier.clickable(enabled = profiles.profiles.isNotEmpty(), onClickLabel = "切换 Host") { hostMenu = true },
                        ) {
                            Text("会话")
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    active?.name ?: "未连接 Host",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                                )
                                if (profiles.profiles.isNotEmpty()) Icon(Icons.Outlined.ArrowDropDown, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        DropdownMenu(expanded = hostMenu, onDismissRequest = { hostMenu = false }) {
                            profiles.profiles.forEach { p ->
                                DropdownMenuItem(
                                    text = { Text(p.name) },
                                    leadingIcon = { if (p.id == active?.id) Icon(Icons.Outlined.Check, "当前") else Spacer(Modifier.size(24.dp)) },
                                    onClick = { hostMenu = false; if (p.id != active?.id) vm.switchHost(p.id) },
                                )
                            }
                            HorizontalDivider()
                            DropdownMenuItem(text = { Text("管理 Host…") }, leadingIcon = { Icon(Icons.Outlined.Dns, null) }, onClick = { hostMenu = false; onOpenHosts() })
                        }
                    }
                },
                actions = {
                    if (active != null) {
                        IconButton(onClick = { searching = !searching; if (!searching) vm.query.value = "" }) {
                            Icon(if (searching) Icons.Outlined.Close else Icons.Outlined.Search, if (searching) "关闭搜索" else "搜索会话")
                        }
                        IconButton(onClick = { creating = true }) { Icon(Icons.Outlined.Add, "新建会话") }
                    }
                    IconButton(onClick = onOpenHosts) { Icon(Icons.Outlined.Dns, "Host 连接") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
            AnimatedVisibility(searching && active != null) {
                OutlinedTextField(
                    value = query, onValueChange = { vm.query.value = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                    placeholder = { Text("搜索标题、内容、项目、模型") },
                    leadingIcon = { Icon(Icons.Outlined.Search, null) },
                    singleLine = true,
                    shape = RoundedCornerShape(24.dp),
                )
            }
            state.error?.let {
                Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.CloudOff, null, tint = MaterialTheme.colorScheme.onErrorContainer)
                        Spacer(Modifier.width(8.dp))
                        Text(it, Modifier.weight(1f), color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodySmall, maxLines = 3)
                        TextButton(onClick = { vm.refresh() }) { Text("重试") }
                    }
                }
            }
            PullToRefreshBox(
                isRefreshing = pulling,
                onRefresh = { pulling = true; vm.refresh() },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                when {
                    active == null -> Empty(Icons.Outlined.Dns, "还没有连接 Host", "添加 Host 后即可查看和创建会话。") {
                        Button(onClick = onOpenHosts) { Text("添加 Host") }
                    }
                    groups.isEmpty() && !state.loading && query.isNotBlank() ->
                        Empty(Icons.Outlined.Search, "没有匹配的会话", "换个关键词试试。") {}
                    groups.isEmpty() && !state.loading && showArchived ->
                        Empty(Icons.Outlined.Archive, "没有归档的会话", "左滑会话可以归档，归档不会删除。") {
                            TextButton(onClick = { vm.showArchived.value = false }) { Text("返回会话") }
                        }
                    groups.isEmpty() && !state.loading -> Empty(Icons.Outlined.PlayCircle, "暂无会话", "在下方直接输入第一句话，就能开始一个新会话。") {}
                    else -> LazyColumn(Modifier.fillMaxSize().testTag("session-list"), contentPadding = PaddingValues(bottom = 8.dp)) {
                        if (showArchived) item(key = "archived-header") {
                            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("已归档", Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                                TextButton(onClick = { vm.showArchived.value = false }) { Text("返回") }
                            }
                        }
                        groups.forEach { group ->
                            stickyHeader(key = "h-${group.key}") { GroupHeader(group.title, group.rows.size) }
                            itemsIndexed(group.rows, key = { _, it -> "${group.key}|${it.session.id}" }) { i, row ->
                                SessionListRow(
                                    row = row,
                                    shape = groupShape(i, group.rows.size),
                                    selected = row.session.id == selectedId,
                                    preview = SessionOverview.previewOf(row.session, prefs.drafts[row.session.id]),
                                    time = SessionOverview.relativeTime(row.session.updatedAt, now / 1000.0),
                                    onOpen = { onOpenChat(vm.remember(row.session)) },
                                    onPin = { haptic.tick(); vm.setPinned(row.session, !row.pinned) },
                                    onArchive = { haptic.tick(); vm.setArchived(row.session, !row.archived) },
                                    onRename = { renaming = row.session },
                                    onDelete = { deleting = row.session },
                                    onLongPress = { haptic.confirm() },
                                    modifier = Modifier.animateItem(),
                                )
                            }
                        }
                        if (!showArchived && archivedCount > 0 && query.isBlank()) item(key = "archived-link") {
                            TextButton(onClick = { vm.showArchived.value = true }, modifier = Modifier.padding(horizontal = 8.dp)) {
                                Icon(Icons.Outlined.Archive, null, Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("已归档（$archivedCount）")
                            }
                        }
                    }
                }
            }
            if (active != null && !showArchived) QuickStartBar(
                // Most recently used project first, so the default is where the user just was.
                projects = projects.map { it.name }.sortedByDescending { name ->
                    state.sessions.filter { it.project == name }.maxOfOrNull { it.updatedAt ?: 0.0 } ?: -1.0
                },
                onStart = { project, text ->
                    haptic.confirm()
                    vm.quickStart(project, text) { onOpenChat(vm.remember(it)) }
                },
            )
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
            text = { Text("会从 Host 删除这个会话，无法恢复。只想收起它可以用“归档”。") },
            confirmButton = { TextButton(onClick = { vm.delete(s); deleting = null }) { Text("删除", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun GroupHeader(title: String, count: Int) {
    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(start = 28.dp, end = 16.dp, top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (title == "置顶") Icon(Icons.Outlined.PushPin, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary)
            if (title == "置顶") Spacer(Modifier.width(4.dp))
            Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(6.dp))
            Text("$count", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private data class StatusLook(val icon: ImageVector, val tint: Color)

@Composable
private fun statusLook(s: SessionStatus): StatusLook = when (s) {
    SessionStatus.NeedsYou -> StatusLook(Icons.Outlined.PanTool, Brand.warning)
    SessionStatus.Running -> StatusLook(Icons.Outlined.PlayCircle, Brand.success)
    SessionStatus.Unread -> StatusLook(Icons.Outlined.FiberManualRecord, MaterialTheme.colorScheme.primary)
    SessionStatus.Idle -> StatusLook(Icons.Outlined.DoneAll, MaterialTheme.colorScheme.onSurfaceVariant)
    SessionStatus.Offline -> StatusLook(Icons.Outlined.CloudOff, MaterialTheme.colorScheme.outline)
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SessionListRow(
    row: SessionRow,
    shape: Shape,
    selected: Boolean,
    preview: String,
    time: String,
    onOpen: () -> Unit,
    onPin: () -> Unit,
    onArchive: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
    onLongPress: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val s = row.session
    val swipe = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    val look = statusLook(row.status)
    SwipeToDismissBox(
        state = swipe,
        modifier = modifier,
        backgroundContent = {
            val toEnd = swipe.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            val bg by animateColorAsState(
                when (swipe.dismissDirection) {
                    SwipeToDismissBoxValue.StartToEnd -> MaterialTheme.colorScheme.primaryContainer
                    SwipeToDismissBoxValue.EndToStart -> MaterialTheme.colorScheme.tertiaryContainer
                    else -> Color.Transparent
                },
                label = "swipe-bg",
            )
            Row(
                Modifier.fillMaxSize().padding(horizontal = Design.screenPadding, vertical = Design.gap / 2).clip(shape).background(bg).padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = if (toEnd) Arrangement.Start else Arrangement.End,
            ) {
                if (swipe.dismissDirection == SwipeToDismissBoxValue.StartToEnd) {
                    Icon(Icons.Outlined.PushPin, null); Spacer(Modifier.width(8.dp)); Text(if (row.pinned) "取消置顶" else "置顶")
                } else if (swipe.dismissDirection == SwipeToDismissBoxValue.EndToStart) {
                    Text(if (row.archived) "取消归档" else "归档"); Spacer(Modifier.width(8.dp))
                    Icon(if (row.archived) Icons.Outlined.Unarchive else Icons.Outlined.Archive, null)
                }
            }
        },
        onDismiss = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> onPin()
                SwipeToDismissBoxValue.EndToStart -> onArchive()
                else -> Unit
            }
            scope.launch { swipe.reset() }
        },
    ) {
        val compact = LocalCompactList.current
        Box {
            ListItem(
                modifier = Modifier
                    .padding(horizontal = Design.screenPadding, vertical = Design.gap / 2)
                    .clip(shape)
                    .combinedClickable(
                        onClick = onOpen,
                        onLongClick = { onLongPress(); menu = true },
                        onLongClickLabel = "更多操作",
                    )
                    .semantics(mergeDescendants = true) {
                        contentDescription = "${s.displayTitle}，${row.status.label}" + if (row.pinned) "，已置顶" else ""
                    },
                colors = ListItemDefaults.colors(
                    containerColor = if (selected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
                ),
                leadingContent = {
                    Box(
                        Modifier.size(if (compact) 30.dp else 40.dp).background(look.tint.copy(alpha = 0.14f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { Icon(look.icon, null, Modifier.size(20.dp), tint = look.tint) }
                },
                headlineContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(s.displayTitle, Modifier.weight(1f, fill = false), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                        if (row.pinned) {
                            Spacer(Modifier.width(4.dp))
                            Icon(Icons.Outlined.PushPin, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                },
                supportingContent = {
                    if (compact) {
                        Text(
                            listOfNotNull(row.status.label, preview.ifEmpty { null }).joinToString(" · "), maxLines = 1, overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (row.status == SessionStatus.NeedsYou) Brand.warning else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else Column {
                        if (preview.isNotEmpty()) Text(
                            preview, maxLines = 2, overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (row.status == SessionStatus.NeedsYou) Brand.warning else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Tag(row.status.label, when (row.status) {
                                SessionStatus.NeedsYou -> Tint.Error
                                SessionStatus.Running -> Tint.Tertiary
                                SessionStatus.Unread -> Tint.Primary
                                else -> Tint.Neutral
                            })
                            s.model?.takeIf { it.isNotBlank() }?.let {
                                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                },
                trailingContent = {
                    if (time.isNotEmpty()) Text(time, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                },
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(if (row.pinned) "取消置顶" else "置顶") }, leadingIcon = { Icon(Icons.Outlined.PushPin, null) }, onClick = { menu = false; onPin() })
                DropdownMenuItem(text = { Text("重命名") }, onClick = { menu = false; onRename() })
                DropdownMenuItem(
                    text = { Text(if (row.archived) "取消归档" else "归档") },
                    leadingIcon = { Icon(if (row.archived) Icons.Outlined.Unarchive else Icons.Outlined.Archive, null) },
                    onClick = { menu = false; onArchive() },
                )
                DropdownMenuItem(text = { Text("删除", color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; onDelete() })
            }
        }
    }
}

/** Denser rows (Settings → 紧凑列表). */
val LocalCompactList = androidx.compose.runtime.staticCompositionLocalOf { false }

/** Start a session by typing its first message (no dialog). */
@Composable
private fun QuickStartBar(projects: List<String>, onStart: (project: String, text: String) -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    var project by rememberSaveable(projects) { mutableStateOf(projects.firstOrNull().orEmpty()) }
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, shape = RoundedCornerShape(topStart = Design.outer, topEnd = Design.outer), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            if (projects.size > 1) LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(bottom = 6.dp)) {
                items(projects, key = { it }) { p ->
                    FilterChip(selected = p == project, onClick = { project = p }, label = { Text(p, maxLines = 1) })
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextField(
                    value = text, onValueChange = { text = it },
                    modifier = Modifier.weight(1f).testTag("quick-start-input"),
                    placeholder = { Text(if (project.isNotEmpty()) "在 $project 开始新会话…" else "输入第一句话开始新会话…", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    maxLines = 4,
                    shape = RoundedCornerShape(24.dp),
                    colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, disabledIndicatorColor = Color.Transparent),
                )
                Spacer(Modifier.width(8.dp))
                FilledIconButton(
                    onClick = { val t = text; text = ""; onStart(project, t) },
                    enabled = text.isNotBlank() && project.isNotBlank(),
                ) { Icon(Icons.AutoMirrored.Filled.Send, "开始新会话") }
            }
        }
    }
}

@Composable
internal fun Empty(icon: ImageVector, title: String, body: String, action: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(72.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
        Spacer(Modifier.height(16.dp))
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(6.dp))
        Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        action()
    }
}
