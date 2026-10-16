package com.huanmeng.huanhermes.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.runtime.rememberCoroutineScope
import com.huanmeng.huanhermes.ui.chat.MarkdownView
import com.huanmeng.huanhermes.ui.chat.MessageActions
import com.huanmeng.huanhermes.ui.chat.ThinkingRow
import com.huanmeng.huanhermes.ui.chat.ToolRow
import kotlinx.coroutines.launch
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.chat.ChatItem
import com.huanmeng.huanhermes.core.chat.ConnectionBanner
import com.huanmeng.huanhermes.ui.vm.ChatViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(vm: ChatViewModel, onBack: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    var input by rememberSaveable { mutableStateOf("") }
    val list = rememberLazyListState()
    val items = state.items

    // Stick to the newest message unless the user scrolled up to read. Re-applied when
    // items arrive, the last one grows (streaming), or the viewport changes size
    // (keyboard, rotation, activity recreation), so the latest reply never ends up
    // hidden below the fold.
    var stick by rememberSaveable { mutableStateOf(true) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(list) {
        snapshotFlow { list.isScrollInProgress }.collect { scrolling ->
            if (!scrolling) stick = !list.canScrollForward
        }
    }
    val viewport by remember { derivedStateOf { list.layoutInfo.viewportSize.height } }
    LaunchedEffect(items.size, items.lastOrNull(), viewport) {
        if (items.isNotEmpty() && stick) list.scrollToItem(items.size - 1, 100_000) // offset is clamped to the end
    }

    Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
        TopAppBar(
            title = {
                Column {
                    Text(vm.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val sub = listOfNotNull(state.model, state.mode, if (state.typing) "正在输入…" else null).joinToString(" · ")
                    if (sub.isNotEmpty()) Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
            actions = { IconButton(onClick = { vm.reload() }) { Icon(Icons.Outlined.Refresh, "重新加载记录") } },
        )
        Banner(state.banner, onRetry = vm::reconnect)
        if (state.reloading) LinearProgressIndicator(Modifier.fillMaxWidth())
        vm.safeError(state.error)?.let {
            Text(it, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(
                state = list,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                itemsIndexed(items, key = { _, it -> it.id }) { i, item ->
                    ChatRow(item, live = state.runActive && i == items.lastIndex, onDecision = { d -> vm.respond(item as ChatItem.Permission, d) })
                }
            }
            // Scrolled up to read: one tap back to the newest message.
            if (!stick && items.isNotEmpty()) {
                SmallFloatingActionButton(
                    onClick = { stick = true; scope.launch { list.animateScrollToItem(items.size - 1, 100_000) } },
                    modifier = Modifier.align(Alignment.BottomEnd).padding(12.dp),
                ) { Icon(Icons.Outlined.KeyboardArrowDown, "回到最新消息") }
            }
        }
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                value = input, onValueChange = { input = it },
                modifier = Modifier.weight(1f).testTag("chat-input"),
                placeholder = { Text(if (state.connected) "发消息…" else "离线：发送后会排队，重连后自动发出") },
                maxLines = 6,
            )
            if (state.runActive) {
                IconButton(onClick = vm::cancel) { Icon(Icons.Outlined.StopCircle, "停止运行") }
            }
            IconButton(onClick = { if (input.isNotBlank()) { vm.send(input); input = ""; stick = true } }, enabled = input.isNotBlank()) {
                Icon(Icons.AutoMirrored.Filled.Send, "发送")
            }
        }
    }
}

@Composable
private fun Banner(banner: ConnectionBanner, onRetry: () -> Unit) {
    val (text, retry) = when (banner) {
        ConnectionBanner.None -> return
        ConnectionBanner.Connecting -> "正在连接 Bridge…" to false
        is ConnectionBanner.Reconnecting ->
            (if (banner.delayMs > 0) "已断开：${banner.reason} · ${(banner.delayMs + 999) / 1000} 秒后第 ${banner.attempt} 次重连" else "已断开，正在重连…") to true
        is ConnectionBanner.Stopped ->
            (if (banner.authFailed) "连接被拒绝：${banner.reason}。请在 Host 连接里检查令牌。" else "已停止：${banner.reason}") to true
    }
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
            if (retry) TextButton(onClick = onRetry) { Text("立即重连") }
        }
    }
}

@Composable
private fun ChatRow(item: ChatItem, live: Boolean, onDecision: (String) -> Unit) {
    when (item) {
        is ChatItem.User -> MessageActions(item.text) {
            Bubble(alignEnd = true, color = MaterialTheme.colorScheme.primaryContainer) {
                Column {
                    Text(item.text, color = MaterialTheme.colorScheme.onPrimaryContainer)
                    if (item.queued) Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Schedule, null, Modifier.padding(end = 4.dp))
                        Text("等待发送（离线队列）", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
        // Agent replies read like a document (full width, Markdown), not a chat bubble.
        is ChatItem.Assistant -> MessageActions(item.text) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 2.dp)) {
                MarkdownView(item.text)
                if (item.streaming) Text("▍", color = MaterialTheme.colorScheme.primary)
            }
        }
        is ChatItem.Thinking -> ThinkingRow(item, live)
        is ChatItem.Tool -> ToolRow(item)
        is ChatItem.Permission -> PermissionCard(item, onDecision)
        is ChatItem.Notice -> Muted(item.text)
        is ChatItem.Failure -> Text(
            "错误：${item.text}${item.code?.let { "（$it）" } ?: ""}",
            color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall,
        )
        is ChatItem.RunEnded -> Muted(
            when (item.status) {
                "completed" -> "— 完成 —"
                "cancelled" -> "— 已取消 —"
                "failed", "error" -> "— 失败${item.exitCode?.let { "（退出码 $it）" } ?: ""} —"
                "timeout" -> "— 超时 —"
                else -> "— ${item.status} —"
            },
        )
        is ChatItem.Unsupported -> Muted("（此版本暂不支持的事件：${item.type}）")
    }
}

@Composable
private fun Bubble(alignEnd: Boolean, color: androidx.compose.ui.graphics.Color, content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = if (alignEnd) Alignment.CenterEnd else Alignment.CenterStart) {
        Box(
            Modifier.widthIn(max = 560.dp)
                .background(color, RoundedCornerShape(14.dp))
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) { content() }
    }
}

@Composable
private fun Muted(text: String, maxLines: Int = Int.MAX_VALUE) {
    Text(
        text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = maxLines, overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun PermissionCard(item: ChatItem.Permission, onDecision: (String) -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("需要权限", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            MarkdownView(item.text, style = MaterialTheme.typography.bodyMedium)
            val decided = item.decision
            if (decided != null) {
                AssistChip(onClick = {}, label = {
                    Text(when (decided) { "allow_all" -> "已始终允许"; "deny" -> "已拒绝"; else -> "已允许" })
                })
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val has = { suffix: String -> item.buttons.any { it.data.endsWith(":$suffix") || it.data == suffix } }
                    if (has("allow") || item.buttons.isEmpty()) Button(onClick = { onDecision("allow") }) { Text("允许") }
                    if (has("allow_all")) OutlinedButton(onClick = { onDecision("allow_all") }) { Text("始终允许") }
                    if (has("deny") || item.buttons.isEmpty()) OutlinedButton(
                        onClick = { onDecision("deny") },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) { Text("拒绝") }
                }
                // Non-permission buttons (plain actions) are offered with their own labels.
                val others = item.buttons.filterNot { b -> listOf("allow", "allow_all", "deny").any { b.data.endsWith(":$it") } }
                others.forEach { b -> TextButton(onClick = { onDecision(b.data) }) { Text(b.text) } }
            }
        }
    }
}
