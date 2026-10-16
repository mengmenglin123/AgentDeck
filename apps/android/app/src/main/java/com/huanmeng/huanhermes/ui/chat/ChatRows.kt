package com.huanmeng.huanhermes.ui.chat

import android.content.Intent
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.core.chat.ChatItem
import com.huanmeng.huanhermes.core.render.ToolView
import kotlinx.coroutines.delay

/**
 * Long-press menu shared by user and assistant messages: copy, select text
 * (a full-screen selectable view, so long-press never fights text selection),
 * share. Code blocks keep their own copy button.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MessageActions(text: String, content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    var selecting by remember { mutableStateOf(false) }
    Box(
        Modifier.combinedClickable(onClick = {}, onLongClick = { menu = true }, onLongClickLabel = "消息操作"),
    ) {
        content()
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("复制") }, leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) }, onClick = {
                menu = false; copyToClipboard(ctx, text)
            })
            DropdownMenuItem(text = { Text("选择文本") }, leadingIcon = { Icon(Icons.Outlined.TextFields, null) }, onClick = {
                menu = false; selecting = true
            })
            DropdownMenuItem(text = { Text("分享") }, leadingIcon = { Icon(Icons.Outlined.Share, null) }, onClick = {
                menu = false
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                runCatching { ctx.startActivity(Intent.createChooser(send, "分享消息")) }
            })
        }
    }
    if (selecting) {
        AlertDialog(
            onDismissRequest = { selecting = false },
            confirmButton = { TextButton(onClick = { copyToClipboard(ctx, text); selecting = false }) { Text("复制全部") } },
            dismissButton = { TextButton(onClick = { selecting = false }) { Text("关闭") } },
            title = { Text("选择文本") },
            text = {
                SelectionContainer(Modifier.verticalScroll(rememberScrollState())) {
                    Text(text, style = MaterialTheme.typography.bodyMedium)
                }
            },
        )
    }
}

/**
 * Reasoning folds away like in RikkaHub / ChatGPT: while the agent is still
 * thinking it shows a live timer and the latest lines; afterwards a one-line
 * "思考过程" header that expands to the full text.
 */
@Composable
fun ThinkingRow(item: ChatItem.Thinking, live: Boolean) {
    var open by rememberSaveable(item.id) { mutableStateOf(false) }
    val startedAt = remember(item.id) { System.currentTimeMillis() }
    var now by remember { mutableLongStateOf(startedAt) }
    var finishedAfter by rememberSaveable(item.id) { mutableLongStateOf(-1L) }
    LaunchedEffect(live) {
        while (live) { now = System.currentTimeMillis(); delay(1_000) }
        if (finishedAfter < 0 && now > startedAt) finishedAfter = (now - startedAt) / 1000
    }
    val seconds = (now - startedAt) / 1000
    val header = when {
        live -> "思考中… ${seconds}s"
        finishedAfter > 0 -> "已思考 ${finishedAfter}s"
        else -> "思考过程"
    }
    Column(
        Modifier.fillMaxWidth().animateContentSize().clickable { open = !open }
            .semantics { contentDescription = "$header，点按${if (open) "收起" else "展开"}" },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Lightbulb, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(header, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 6.dp))
            Icon(if (open) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val muted = MaterialTheme.colorScheme.onSurfaceVariant
        when {
            open -> MarkdownView(item.text, Modifier.padding(start = 22.dp, top = 4.dp), MaterialTheme.typography.bodyMedium, muted)
            live -> Text(
                item.text.trimEnd().lines().takeLast(2).joinToString("\n"),
                style = MaterialTheme.typography.bodySmall, color = muted, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 22.dp, top = 2.dp),
            )
        }
    }
}

private fun ToolView.Kind.icon(): ImageVector = when (this) {
    ToolView.Kind.Shell -> Icons.Outlined.Terminal
    ToolView.Kind.Edit, ToolView.Kind.Patch -> Icons.Outlined.Edit
    ToolView.Kind.Write -> Icons.Outlined.Description
    ToolView.Kind.Read -> Icons.Outlined.Visibility
    ToolView.Kind.Search -> Icons.Outlined.Search
    ToolView.Kind.Todo -> Icons.Outlined.Checklist
    ToolView.Kind.Web -> Icons.Outlined.Public
    ToolView.Kind.Agent -> Icons.Outlined.AccountTree
    ToolView.Kind.Mcp -> Icons.Outlined.Extension
    ToolView.Kind.Generic -> Icons.Outlined.Build
}

/**
 * One card per tool call, drawn by kind (Happy-style): shell shows the command
 * and its output, edits show a diff, todo lists show checkboxes. Edits and todos
 * open by default; everything else stays a one-line summary until tapped.
 */
@Composable
fun ToolRow(item: ChatItem.Tool) {
    val view = remember(item.name, item.input, item.output) { ToolView.of(item.name, item.input, item.output) }
    val openByDefault = view.kind in setOf(ToolView.Kind.Edit, ToolView.Kind.Write, ToolView.Kind.Patch, ToolView.Kind.Todo)
    var open by rememberSaveable(item.id) { mutableStateOf(openByDefault) }
    val status = when {
        !item.finished -> "运行中"
        item.isError -> "失败"
        else -> "完成"
    }
    OutlinedCard(Modifier.fillMaxWidth().animateContentSize()) {
        Column {
            Row(
                Modifier.fillMaxWidth().clickable { open = !open }.padding(horizontal = 12.dp, vertical = 10.dp)
                    .semantics { contentDescription = "工具 ${view.title}，$status，点按${if (open) "收起" else "展开"}" },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(view.kind.icon(), null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                    Text(view.title, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    view.subtitle?.let {
                        Text(
                            it, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                when {
                    !item.finished -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    item.isError -> Icon(Icons.Outlined.ErrorOutline, "失败", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
                    else -> Icon(Icons.Outlined.CheckCircle, "完成", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (open) Column(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ToolBody(view, item.isError)
            }
        }
    }
}

@Composable
private fun ToolBody(v: ToolView, isError: Boolean) {
    val out = v.output?.let { if (it.length > 40_000) it.take(40_000) + "\n…（已截断）" else it }
    when (v.kind) {
        ToolView.Kind.Shell -> {
            v.command?.let { CodeBlockView("$ $it", "shell", title = "命令", foldLines = 8) }
            out?.takeIf { it.isNotBlank() }?.let { CodeBlockView(it, null, title = if (isError) "输出（错误）" else "输出", foldLines = 16) }
        }
        ToolView.Kind.Edit, ToolView.Kind.Write, ToolView.Kind.Patch -> {
            if (v.diff.isNotEmpty()) DiffView(v.diff, v.language)
            v.files.forEach { (path, kind) ->
                val label = when (kind) { "add", "create" -> "新增"; "delete", "remove" -> "删除"; else -> "修改" }
                Text("$label  $path", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
            }
            out?.takeIf { it.isNotBlank() && isError }?.let { CodeBlockView(it, null, title = "错误", foldLines = 8) }
        }
        ToolView.Kind.Todo -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            v.todos.forEach { t ->
                val (mark, color) = when (t.status) {
                    "completed", "done" -> "☑" to MaterialTheme.colorScheme.onSurfaceVariant
                    "in_progress", "active" -> "◐" to MaterialTheme.colorScheme.primary
                    else -> "☐" to MaterialTheme.colorScheme.onSurface
                }
                Row {
                    Text(mark, color = color, modifier = Modifier.padding(end = 8.dp))
                    Text(t.text, color = color, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        ToolView.Kind.Read -> out?.takeIf { it.isNotBlank() }?.let { CodeBlockView(it, v.language, title = v.path, foldLines = 16) }
        else -> {
            v.input?.takeIf { it.isNotBlank() && it != "{}" }?.let { CodeBlockView(it, "json", title = "参数", foldLines = 12) }
            out?.takeIf { it.isNotBlank() }?.let { CodeBlockView(it, null, title = if (isError) "结果（错误）" else "结果", foldLines = 16) }
        }
    }
}
