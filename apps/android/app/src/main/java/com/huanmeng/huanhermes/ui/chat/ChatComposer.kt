package com.huanmeng.huanhermes.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.OpenInFull
import androidx.compose.material.icons.outlined.CloseFullscreen
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.core.chat.ChatItem
import com.huanmeng.huanhermes.core.chat.ChatRowModel
import com.huanmeng.huanhermes.core.chat.ConnectionBanner
import com.huanmeng.huanhermes.core.chat.QueuedSend
import com.huanmeng.huanhermes.core.chat.SlashCommand
import com.huanmeng.huanhermes.core.chat.SlashCommands
import com.huanmeng.huanhermes.core.net.Diagnostics
import com.huanmeng.huanhermes.ui.theme.Brand

@Composable
fun ChatEmpty(onPick: (String) -> Unit) {
    val prompts = listOf("解释一下这个项目的结构", "运行测试并修复失败的用例", "看看最近的 git 改动", "/status")
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Outlined.AutoAwesome, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.size(12.dp))
        Text("从一句话开始", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.size(12.dp))
        prompts.forEachIndexed { i, p ->
            Surface(onClick = { onPick(p) }, shape = com.huanmeng.huanhermes.ui.components.groupShape(i, prompts.size, 18.dp, 6.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.widthIn(max = 420.dp).fillMaxWidth().padding(vertical = 1.dp)) {
                Text(p, Modifier.padding(horizontal = 16.dp, vertical = 13.dp), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** A finished turn's tool calls and thinking, as one line that expands. */
@Composable
fun FoldedWorkRow(row: ChatRowModel.FoldedWork) {
    var open by rememberSaveable(row.key) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().animateContentSize()) {
        Row(
            Modifier.clickable { open = !open }.padding(vertical = 4.dp)
                .semantics { contentDescription = "${row.summary}，点按${if (open) "收起" else "展开"}" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Build, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(row.summary, Modifier.padding(horizontal = 6.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (row.failedTools > 0) Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error)
            Icon(if (open) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (open) Column(Modifier.padding(start = 8.dp, top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            row.children.forEach { child ->
                when (child) {
                    is ChatItem.Thinking -> ThinkingRow(child, live = false)
                    is ChatItem.Tool -> ToolRow(child)
                    else -> Unit
                }
            }
        }
    }
}

@Composable
fun RunQueue(queue: List<QueuedSend>, onEdit: (String) -> Unit, onSendNow: (String) -> Unit, onRemove: (String) -> Unit) {
    AnimatedVisibility(queue.isNotEmpty()) {
        Surface(color = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) {
                Text("排队中（${queue.size}）· 本轮结束后依次发送", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                queue.forEach { q ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Schedule, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(q.text, Modifier.weight(1f).padding(horizontal = 6.dp), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
                        IconButton(onClick = { onEdit(q.msgId) }) { Icon(Icons.Outlined.Edit, "编辑排队消息", Modifier.size(18.dp)) }
                        IconButton(onClick = { onSendNow(q.msgId) }) { Icon(Icons.Outlined.Bolt, "立即发送", Modifier.size(18.dp)) }
                        IconButton(onClick = { onRemove(q.msgId) }) { Icon(Icons.Outlined.Close, "移除排队消息", Modifier.size(18.dp)) }
                    }
                }
            }
        }
    }
}

@Composable
fun SlashPalette(input: String, onPick: (SlashCommand) -> Unit) {
    val suggestions = remember(input) { SlashCommands.suggestions(input) }
    AnimatedVisibility(suggestions.isNotEmpty()) {
        Surface(tonalElevation = 2.dp, modifier = Modifier.fillMaxWidth().heightIn(max = 240.dp)) {
            LazyColumn(Modifier.testTag("slash-palette")) {
                items(suggestions, key = { it.command }) { c ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onPick(c) }.padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(c.command, style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace), color = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(12.dp))
                        Text(c.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/** `@` file picker; shows nothing when the Host has no `file_search` or nothing matches. */
@Composable
fun MentionPalette(visible: Boolean, files: List<String>, onPick: (String) -> Unit) {
    AnimatedVisibility(visible && files.isNotEmpty()) {
        Surface(tonalElevation = 2.dp, modifier = Modifier.fillMaxWidth().heightIn(max = 240.dp)) {
            LazyColumn(Modifier.testTag("mention-palette")) {
                items(files, key = { it }) { path ->
                    val name = path.substringAfterLast('/')
                    val dir = path.substringBeforeLast('/', "")
                    Row(
                        Modifier.fillMaxWidth().clickable { onPick(path) }.padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.Description, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                        Column(Modifier.padding(start = 10.dp)) {
                            Text(name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (dir.isNotEmpty()) Text(dir, style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace), color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

fun modeLabel(mode: String?) = when (mode) {
    null, "", "default" -> "默认模式"
    "plan" -> "计划模式"
    "acceptEdits" -> "自动接受编辑"
    "bypassPermissions" -> "跳过权限"
    else -> mode
}

@Composable
fun Composer(
    input: String,
    onInput: (String) -> Unit,
    connected: Boolean,
    runActive: Boolean,
    queues: Boolean,
    model: String?,
    mode: String?,
    models: List<String>,
    history: List<String>,
    onSend: () -> Unit,
    onCommand: (String) -> Unit,
    onCancel: () -> Unit,
    onVoice: (() -> Unit)? = null,
    onAttach: (() -> Unit)? = null,
    attachCount: Int = 0,
) {
    val prefs = LocalChatPrefs.current
    var fullEditor by remember { mutableStateOf(false) }
    var modelMenu by remember { mutableStateOf(false) }
    var modeMenu by remember { mutableStateOf(false) }
    var historyMenu by remember { mutableStateOf(false) }
    val trySend = { if (input.isNotBlank()) onSend() }
    Column(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 4.dp, bottom = 8.dp)) {
        if (input.isEmpty() && prefs.quickMessages.isNotEmpty()) {
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(bottom = 6.dp).testTag("quick-messages"),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                prefs.quickMessages.forEach { q ->
                    Surface(onClick = { onInput(q) }, shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                        Text(q, Modifier.padding(horizontal = 10.dp, vertical = 6.dp), style = MaterialTheme.typography.labelMedium, maxLines = 1)
                    }
                }
            }
        }
        // One rounded container: the text on top, tools and send in a row underneath.
        Surface(shape = RoundedCornerShape(26.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(start = 6.dp, end = 6.dp, top = 2.dp, bottom = 6.dp)) {
                TextField(
                    value = input, onValueChange = onInput,
                    keyboardOptions = if (prefs.enterToSend) androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Send) else androidx.compose.foundation.text.KeyboardOptions.Default,
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSend = { trySend() }),
                    modifier = Modifier.fillMaxWidth().testTag("chat-input").onPreviewKeyEvent { e ->
                        // Hardware keyboards: Enter sends, Shift+Enter is a new line.
                        if (prefs.enterToSend && e.key == Key.Enter && !e.isShiftPressed) {
                            if (e.type == KeyEventType.KeyDown) trySend()
                            true
                        } else false
                    },
                    placeholder = {
                        Text(
                            when {
                                !connected -> "离线：发送后会排队，重连后自动发出"
                                runActive && queues -> "运行中：新消息会排在本轮之后"
                                else -> "发消息，/ 命令，@ 文件…"
                            },
                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    },
                    maxLines = 8,
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent, disabledContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, disabledIndicatorColor = Color.Transparent,
                    ),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box {
                        Surface(
                            onClick = { modelMenu = true }, shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.surfaceContainerHighest,
                            modifier = Modifier.semantics { contentDescription = "切换模型，当前 ${model ?: "默认"}" },
                        ) {
                            Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.AutoAwesome, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(4.dp))
                                Text(model ?: "模型", Modifier.widthIn(max = 120.dp), style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                        DropdownMenu(expanded = modelMenu, onDismissRequest = { modelMenu = false }) {
                            if (models.isEmpty()) DropdownMenuItem(text = { Text("Host 未提供模型列表，输入 /model 名称") }, onClick = { modelMenu = false; onInput("/model ") })
                            models.forEach { m ->
                                DropdownMenuItem(
                                    text = { Text(m) },
                                    leadingIcon = { if (m == model) Icon(Icons.Outlined.Check, "当前") },
                                    onClick = { modelMenu = false; if (m != model) onCommand(SlashCommands.modelCommand(m)) },
                                )
                            }
                        }
                    }
                    Box {
                        IconButton(onClick = { modeMenu = true }, modifier = Modifier.semantics { contentDescription = "切换模式，当前 ${modeLabel(mode)}" }) {
                            Icon(Icons.Outlined.Tune, null, tint = if (mode == "plan") MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        DropdownMenu(expanded = modeMenu, onDismissRequest = { modeMenu = false }) {
                            SlashCommands.MODES.forEach { m ->
                                DropdownMenuItem(
                                    text = { Text(modeLabel(m)) },
                                    leadingIcon = { if (m == (mode ?: "default")) Icon(Icons.Outlined.Check, "当前") },
                                    onClick = { modeMenu = false; if (m != mode) onCommand(SlashCommands.modeCommand(m)) },
                                )
                            }
                        }
                    }
                    if (onAttach != null) IconButton(onClick = onAttach, modifier = Modifier.testTag("attach-chip")) {
                        androidx.compose.material3.BadgedBox(badge = { if (attachCount > 0) androidx.compose.material3.Badge { Text("$attachCount") } }) {
                            Icon(Icons.Outlined.AttachFile, if (attachCount > 0) "附件 $attachCount" else "附件", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    var more by remember { mutableStateOf(false) }
                    Box {
                        IconButton(onClick = { more = true }) { Icon(Icons.Outlined.AddCircleOutline, "插入", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                        DropdownMenu(expanded = more, onDismissRequest = { more = false }) {
                            DropdownMenuItem(text = { Text("/ 命令") }, onClick = { more = false; onInput("/") })
                            DropdownMenuItem(text = { Text("@ 文件") }, onClick = { more = false; onInput(if (input.isEmpty() || input.endsWith(" ")) input + "@" else "$input @") })
                            if (history.isNotEmpty()) DropdownMenuItem(text = { Text("历史输入") }, leadingIcon = { Icon(Icons.Outlined.History, null) }, onClick = { more = false; historyMenu = true })
                        }
                        DropdownMenu(expanded = historyMenu, onDismissRequest = { historyMenu = false }) {
                            history.take(15).forEach { h ->
                                DropdownMenuItem(text = { Text(h, maxLines = 2, overflow = TextOverflow.Ellipsis) }, onClick = { historyMenu = false; onInput(h) })
                            }
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    if (input.lines().size > 3 || input.length > 160) {
                        IconButton(onClick = { fullEditor = true }) { Icon(Icons.Outlined.OpenInFull, "全屏编辑") }
                    }
                    if (runActive) {
                        IconButton(onClick = onCancel) { Icon(Icons.Outlined.StopCircle, "停止运行", tint = MaterialTheme.colorScheme.error) }
                    }
                    if (input.isEmpty() && onVoice != null) {
                        IconButton(onClick = onVoice, modifier = Modifier.testTag("voice-input")) { Icon(Icons.Outlined.Mic, "语音输入", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    FilledIconButton(onClick = onSend, enabled = input.isNotBlank() || attachCount > 0) {
                        Icon(Icons.Outlined.ArrowUpward, "发送")
                    }
                }
            }
        }
    }
    if (fullEditor) FullScreenEditor(input, onInput, onDismiss = { fullEditor = false }, onSend = { fullEditor = false; trySendOutside(input, onSend) })
}

private fun trySendOutside(input: String, onSend: () -> Unit) { if (input.isNotBlank()) onSend() }

/** Long prompts get the whole screen; the text is the same state as the composer's. */
@Composable
fun FullScreenEditor(input: String, onInput: (String) -> Unit, onDismiss: () -> Unit, onSend: () -> Unit) {
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().imePadding().padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onDismiss) { Icon(Icons.Outlined.CloseFullscreen, "收起编辑器") }
                    Text("编辑消息 · ${input.length} 字", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    FilledIconButton(onClick = onSend, enabled = input.isNotBlank()) { Icon(Icons.AutoMirrored.Filled.Send, "发送") }
                }
                TextField(
                    value = input, onValueChange = onInput,
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(top = 8.dp).testTag("full-editor"),
                    colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
                )
            }
        }
    }
}

/** Only shows when something is wrong; one tap to reconnect or diagnose. */
@Composable
fun HealthStrip(banner: ConnectionBanner, onRetry: () -> Unit, onDiagnose: () -> Unit) {
    val (text, retry) = when (banner) {
        ConnectionBanner.None -> return
        ConnectionBanner.Connecting -> "正在连接 Bridge…" to false
        is ConnectionBanner.Reconnecting ->
            (if (banner.delayMs > 0) "已断开：${banner.reason} · ${(banner.delayMs + 999) / 1000} 秒后第 ${banner.attempt} 次重连" else "已断开，正在重连…") to true
        is ConnectionBanner.Stopped ->
            (if (banner.authFailed) "连接被拒绝：${banner.reason}。请在 Host 连接里检查令牌。" else "已停止：${banner.reason}") to true
    }
    val warn = banner !is ConnectionBanner.Connecting
    Surface(color = if (warn) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.secondaryContainer, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (warn) Icon(Icons.Outlined.WifiOff, null, Modifier.size(16.dp))
            Text(text, Modifier.weight(1f).padding(horizontal = 6.dp), style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (retry) {
                TextButton(onClick = onDiagnose) { Text("诊断") }
                TextButton(onClick = onRetry) { Text("立即重连") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiagnosticsSheet(
    bridgeConnected: Boolean,
    capabilities: Set<String>,
    lastError: String?,
    report: () -> String,
    onReconnect: () -> Unit,
    onDismiss: () -> Unit,
) {
    @Suppress("DEPRECATION")
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("连接诊断", style = MaterialTheme.typography.titleMedium)
            Diagnostics.checks(bridgeConnected, null, capabilities, lastError).forEach { c ->
                Row(verticalAlignment = Alignment.Top) {
                    val icon = when (c.ok) { true -> Icons.Outlined.CheckCircle; false -> Icons.Outlined.ErrorOutline; null -> Icons.AutoMirrored.Outlined.HelpOutline }
                    val tint = when (c.ok) { true -> Brand.success; false -> MaterialTheme.colorScheme.error; null -> MaterialTheme.colorScheme.onSurfaceVariant }
                    Icon(icon, null, Modifier.size(18.dp), tint = tint)
                    Column(Modifier.padding(start = 8.dp)) {
                        Text(c.label + when (c.ok) { true -> "：正常"; false -> "：异常"; null -> "：未知" }, style = MaterialTheme.typography.bodyMedium)
                        if (c.detail.isNotBlank()) Text(c.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            HorizontalDivider()
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onReconnect) { Text("立即重连") }
                OutlinedButton(onClick = { clipboard.setText(AnnotatedString(report())); copied = true }) {
                    Icon(Icons.Outlined.ContentCopy, null, Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(if (copied) "已复制（令牌已隐藏）" else "复制诊断信息")
                }
            }
        }
    }
}

/** Only the decisions the Host's card actually offers; older Hosts keep working. */
@Composable
fun PermissionButtons(buttonData: List<String>, onDecision: (String) -> Unit) {
    val has = { suffix: String -> buttonData.any { it.endsWith(":$suffix") || it == suffix } }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (has("allow") || buttonData.isEmpty()) Button(onClick = { onDecision("allow") }) { Text("允许本次") }
        if (has("allow_all")) OutlinedButton(onClick = { onDecision("allow_all") }) { Text("本会话允许") }
        if (has("deny") || buttonData.isEmpty()) OutlinedButton(
            onClick = { onDecision("deny") },
            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
        ) { Text("拒绝") }
    }
}
