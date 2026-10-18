package com.huanmeng.huanhermes.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.material.icons.outlined.Close
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.mgmt.ProjectInfo
import com.huanmeng.huanhermes.core.workspace.DiffLine
import com.huanmeng.huanhermes.core.workspace.FileDiff
import com.huanmeng.huanhermes.core.workspace.Workspace
import com.huanmeng.huanhermes.core.workspace.WsNode
import com.huanmeng.huanhermes.ui.chat.codePalette
import com.huanmeng.huanhermes.ui.chat.copyToClipboard
import com.huanmeng.huanhermes.ui.chat.highlight
import com.huanmeng.huanhermes.ui.vm.GitViewModel
import com.huanmeng.huanhermes.ui.vm.WorkspaceViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun ProjectChips(projects: List<ProjectInfo>, selected: String?, onSelect: (String?) -> Unit) {
    if (projects.size <= 1) return
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        projects.forEach { p ->
            val isSel = selected == p.name || selected == null && p == projects.first()
            FilterChip(selected = isSel, onClick = { onSelect(p.name) }, label = { Text(p.name) })
        }
    }
}

@Composable
private fun Unsupported(what: String) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("这个 Host 还不支持$what", style = MaterialTheme.typography.titleMedium)
        Text("升级 Host companion 后就能使用", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Highlighted file lines; highlighting runs on a background thread. */
@Composable
private fun rememberHighlightedLines(text: String, language: String): List<AnnotatedString> {
    val p = codePalette()
    val plain = remember(text) { text.split('\n').map { AnnotatedString(it) } }
    val lines by produceState(plain, text, language, p) {
        if (language.isEmpty() || text.length > 400_000) return@produceState
        value = withContext(Dispatchers.Default) {
            val full = highlight(text, language, p)
            var start = 0
            text.split('\n').map { line ->
                val end = start + line.length
                val sub = full.subSequence(start, end)
                start = end + 1
                sub
            }
        }
    }
    return lines
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceScreen(vm: WorkspaceViewModel, onBack: () -> Unit) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val node = ui.node
    BackHandler(enabled = node != null && node.path.isNotEmpty()) { vm.up() }
    val context = LocalContext.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(if (node is WsNode.File) node.name else "Workspace", maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOf(ui.hostName, node?.path?.ifEmpty { "/" } ?: "").filter { it.isNotEmpty() }.joinToString(" · "),
                            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                },
                navigationIcon = { IconButton(onClick = { if (!vm.up()) onBack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = {
                    if (node is WsNode.File && !node.binary) IconButton(onClick = { copyToClipboard(context, node.content) }) { Icon(Icons.Outlined.ContentCopy, "复制") }
                    IconButton(onClick = { vm.open(node?.path.orEmpty()) }) { Icon(Icons.Outlined.Refresh, "刷新") }
                },
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().testTag("workspace-screen")) {
            if (ui.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            ProjectChips(ui.projects, ui.project, vm::selectProject)
            ui.error?.takeIf { !ui.unsupported }?.let { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
            when {
                ui.unsupported -> Unsupported("浏览工作区")
                node is WsNode.Dir -> {
                    Breadcrumb(node.path) { vm.open(it) }
                    LazyColumn(Modifier.fillMaxSize()) {
                        if (node.entries.isEmpty()) item { Text("空目录", Modifier.padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        items(node.entries, key = { it.name }) { e ->
                            ListItem(
                                modifier = Modifier.clickable { vm.open(Workspace.child(node.path, e.name)) }.testTag("ws-entry-${e.name}"),
                                colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                                leadingContent = { Icon(if (e.isDir) Icons.Outlined.Folder else Icons.Outlined.Description, null, tint = if (e.isDir) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) },
                                headlineContent = { Text(e.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                trailingContent = { if (!e.isDir) Text(Workspace.humanSize(e.size), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                            )
                        }
                    }
                }
                node is WsNode.File -> FileView(node)
            }
        }
    }
}

@Composable
private fun Breadcrumb(path: String, onOpen: (String) -> Unit) {
    val parts = if (path.isEmpty()) emptyList() else path.split('/')
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = { onOpen("") }) { Text("根目录") }
        parts.forEachIndexed { i, name ->
            Text("/", color = MaterialTheme.colorScheme.outline)
            TextButton(onClick = { onOpen(parts.take(i + 1).joinToString("/")) }, enabled = i < parts.lastIndex) { Text(name) }
        }
    }
}

@Composable
private fun FileView(file: WsNode.File) {
    if (file.binary) {
        Text("二进制文件（${Workspace.humanSize(file.size)}），不显示内容", Modifier.padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    val lines = rememberHighlightedLines(file.content.trimEnd('\n'), Workspace.languageOf(file.path))
    val gutter = lines.size.toString().length
    val p = codePalette()
    Column(Modifier.fillMaxSize().background(p.background)) {
        if (file.truncated) Text("文件较大，只显示前 256 KB", Modifier.padding(8.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.tertiary)
        Box(Modifier.fillMaxSize().horizontalScroll(rememberScrollState())) {
            LazyColumn(Modifier.fillMaxSize().testTag("file-view"), contentPadding = PaddingValues(vertical = 8.dp)) {
                itemsIndexed(lines) { i, line ->
                    Row {
                        Text((i + 1).toString().padStart(gutter), Modifier.padding(start = 8.dp, end = 12.dp),
                            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), color = MaterialTheme.colorScheme.outline)
                        Text(line, Modifier.padding(end = 16.dp), style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace, fontSize = 12.5.sp), softWrap = false)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GitScreen(
    vm: GitViewModel,
    onBack: () -> Unit,
    sessions: List<com.huanmeng.huanhermes.core.mgmt.SessionInfo> = emptyList(),
    onSendReview: (com.huanmeng.huanhermes.core.mgmt.SessionInfo, String) -> Unit = { _, _ -> },
) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    var pickSession by remember { mutableStateOf(false) }
    BackHandler(enabled = ui.diff != null) { vm.closeDiff() }
    if (pickSession) ReviewSessionPicker(sessions, onPick = { s -> pickSession = false; onSendReview(s, vm.reviewMessage()) }, onDismiss = { pickSession = false })
    val diff = ui.diff
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(diff?.path?.substringAfterLast('/') ?: "改动", maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val sub = if (diff != null) "+${diff.added} −${diff.removed}" else listOfNotNull(ui.hostName.ifEmpty { null }, ui.status?.branch).joinToString(" · ")
                        Text(sub, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = { IconButton(onClick = { if (diff != null) vm.closeDiff() else onBack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = { IconButton(onClick = { if (diff != null) vm.openDiff(diff.path) else vm.refresh() }) { Icon(Icons.Outlined.Refresh, "刷新") } },
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().testTag("git-screen")) {
            if (ui.loading || ui.diffLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
            when {
                ui.unsupported -> Unsupported("查看改动")
                diff != null -> Box(Modifier.weight(1f)) {
                    DiffView(diff, onComment = { line, code, note -> vm.addComment(diff.path, line, code, note) })
                }
                else -> {
                    ProjectChips(ui.projects, ui.project, vm::selectProject)
                    ui.error?.let { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
                    val st = ui.status
                    if (st != null && st.clean) {
                        Text(st.note ?: "工作区很干净，没有改动", Modifier.padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(st?.files.orEmpty(), key = { it.path }) { f ->
                            Card(
                                Modifier.fillMaxWidth().clickable { vm.openDiff(f.path) }.testTag("git-file-${f.path}"),
                                shape = RoundedCornerShape(14.dp),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                            ) {
                                Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    StatusBadge(f.status)
                                    Column(Modifier.padding(start = 12.dp).weight(1f)) {
                                        Text(f.path.substringAfterLast('/'), style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        val dir = f.path.substringBeforeLast('/', "")
                                        if (dir.isNotEmpty()) Text(dir, style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace), color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                    Text(f.label + if (f.staged) " · 已暂存" else "", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            if (ui.comments.isNotEmpty()) {
                androidx.compose.material3.Surface(tonalElevation = 3.dp, modifier = Modifier.fillMaxWidth().testTag("review-bar")) {
                    Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) {
                        ui.comments.forEachIndexed { idx, c ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("${c.path.substringAfterLast('/')}${c.line?.let { ":$it" } ?: ""}  ${c.note}", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                IconButton(onClick = { vm.removeComment(idx) }) { Icon(Icons.Outlined.Close, "删除批注") }
                            }
                        }
                        androidx.compose.material3.Button(onClick = { pickSession = true }, modifier = Modifier.fillMaxWidth()) {
                            Text("把 ${ui.comments.size} 条批注发到会话")
                        }
                    }
                }
            }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReviewSessionPicker(sessions: List<com.huanmeng.huanhermes.core.mgmt.SessionInfo>, onPick: (com.huanmeng.huanhermes.core.mgmt.SessionInfo) -> Unit, onDismiss: () -> Unit) {
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss) {
        Text("发到哪个会话？批注会放进输入框，确认后再发送", Modifier.padding(horizontal = 20.dp, vertical = 8.dp), style = MaterialTheme.typography.titleSmall)
        if (sessions.isEmpty()) Text("当前 Host 没有会话", Modifier.padding(20.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        LazyColumn(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            items(sessions, key = { it.id }) { s ->
                androidx.compose.material3.ListItem(
                    headlineContent = { Text(s.displayTitle, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    supportingContent = { if (s.project.isNotBlank()) Text(s.project) },
                    modifier = Modifier.clickable { onPick(s) },
                )
            }
        }
    }
}

@Composable
private fun StatusBadge(status: String) {
    val p = codePalette()
    val color = when (status) { "A", "?" -> p.added; "D" -> p.removed; "U" -> MaterialTheme.colorScheme.error; else -> p.meta }
    Surface(shape = RoundedCornerShape(6.dp), color = color.copy(alpha = 0.16f)) {
        Text(status, Modifier.size(width = 24.dp, height = 22.dp).padding(top = 2.dp), color = color,
            style = MaterialTheme.typography.labelLarge.copy(fontFamily = FontFamily.Monospace), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DiffView(diff: FileDiff, onComment: (line: Int?, code: String, note: String) -> Unit = { _, _, _ -> }) {
    var commenting by remember { mutableStateOf<com.huanmeng.huanhermes.core.workspace.DiffLine?>(null) }
    commenting?.let { target ->
        var note by remember(target) { mutableStateOf("") }
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { commenting = null },
            title = { Text("批注 ${target.newNo ?: target.oldNo ?: ""} 行") },
            text = {
                Column {
                    Text(target.text.take(200), style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), maxLines = 3, overflow = TextOverflow.Ellipsis)
                    androidx.compose.material3.OutlinedTextField(note, { note = it }, Modifier.fillMaxWidth().padding(top = 8.dp).testTag("review-note"), placeholder = { Text("希望 Agent 怎么改") })
                }
            },
            confirmButton = { TextButton(onClick = { onComment(target.newNo ?: target.oldNo, target.text, note); commenting = null }, enabled = note.isNotBlank()) { Text("添加") } },
            dismissButton = { TextButton(onClick = { commenting = null }) { Text("取消") } },
        )
    }
    val p = codePalette()
    val lang = Workspace.languageOf(diff.path)
    // Highlight code lines once, off the main thread (the "async highlight" from the plan).
    val code by produceState<List<AnnotatedString>?>(null, diff, p) {
        value = withContext(Dispatchers.Default) { diff.lines.map { if (it.kind == DiffLine.Kind.Meta || it.kind == DiffLine.Kind.Hunk || lang.isEmpty()) AnnotatedString(it.text) else highlight(it.text, lang, p) } }
    }
    if (diff.lines.isEmpty()) {
        Text("没有可显示的改动", Modifier.padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    val w = (diff.lines.maxOfOrNull { maxOf(it.oldNo ?: 0, it.newNo ?: 0) } ?: 0).toString().length
    Box(Modifier.fillMaxSize().background(p.background).horizontalScroll(rememberScrollState())) {
        LazyColumn(Modifier.fillMaxSize().testTag("diff-view"), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (diff.truncated) item { Text("改动较大，只显示前 512 KB", Modifier.padding(8.dp), color = MaterialTheme.colorScheme.tertiary) }
            itemsIndexed(diff.lines) { i, line ->
                val bg = when (line.kind) {
                    DiffLine.Kind.Add -> p.addedBg
                    DiffLine.Kind.Del -> p.removedBg
                    DiffLine.Kind.Hunk -> p.meta.copy(alpha = 0.10f)
                    else -> androidx.compose.ui.graphics.Color.Transparent
                }
                val mono = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace, fontSize = 12.5.sp)
                Row(
                    Modifier.background(bg)
                        .then(if (line.kind == DiffLine.Kind.Hunk || line.kind == DiffLine.Kind.Meta) Modifier else Modifier.combinedClickable(onClick = {}, onLongClick = { commenting = line }, onLongClickLabel = "添加批注"))
                        .padding(vertical = 1.dp),
                ) {
                    if (line.kind == DiffLine.Kind.Hunk || line.kind == DiffLine.Kind.Meta) {
                        Text(line.text, Modifier.padding(horizontal = 8.dp, vertical = 2.dp), style = mono, color = if (line.kind == DiffLine.Kind.Hunk) p.meta else MaterialTheme.colorScheme.outline, softWrap = false)
                    } else {
                        Text((line.oldNo?.toString() ?: "").padStart(w), Modifier.padding(start = 6.dp), style = mono, color = MaterialTheme.colorScheme.outline)
                        Text((line.newNo?.toString() ?: "").padStart(w), Modifier.padding(start = 6.dp), style = mono, color = MaterialTheme.colorScheme.outline)
                        val sign = when (line.kind) { DiffLine.Kind.Add -> "+"; DiffLine.Kind.Del -> "−"; else -> " " }
                        Text(sign, Modifier.width(18.dp).padding(start = 6.dp), style = mono, color = if (line.kind == DiffLine.Kind.Add) p.added else p.removed)
                        Text(code?.getOrNull(i) ?: AnnotatedString(line.text), Modifier.padding(end = 16.dp), style = mono, softWrap = false)
                    }
                }
            }
            item { Spacer(Modifier.height(8.dp)) }
        }
    }
}
