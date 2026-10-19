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
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.KeyboardDoubleArrowDown
import androidx.compose.material.icons.outlined.KeyboardDoubleArrowUp
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Description
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import com.huanmeng.huanhermes.core.chat.ChatRowModel
import com.huanmeng.huanhermes.core.chat.TurnFolding
import com.huanmeng.huanhermes.ui.chat.ChatEmpty
import com.huanmeng.huanhermes.ui.chat.Composer
import com.huanmeng.huanhermes.ui.chat.DiagnosticsSheet
import com.huanmeng.huanhermes.ui.chat.FoldedWorkRow
import com.huanmeng.huanhermes.ui.chat.HealthStrip
import com.huanmeng.huanhermes.ui.chat.PermissionButtons
import com.huanmeng.huanhermes.ui.chat.RunQueue
import com.huanmeng.huanhermes.ui.chat.SlashPalette
import com.huanmeng.huanhermes.ui.chat.MentionPalette
import com.huanmeng.huanhermes.ui.rememberHaptic
import com.huanmeng.huanhermes.ui.theme.Brand

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(vm: ChatViewModel, onBack: () -> Unit, foldTurns: Boolean = true, onOpenDiff: (path: String?, project: String?) -> Unit = { _, _ -> }) {
    val state by vm.state.collectAsStateWithLifecycle()
    val history by vm.history.collectAsStateWithLifecycle()
    val models by vm.models.collectAsStateWithLifecycle()
    val fileHits by vm.fileHits.collectAsStateWithLifecycle()
    var input by rememberSaveable { mutableStateOf(vm.initialDraft) }
    var showDiagnostics by remember { mutableStateOf(false) }
    val list = rememberLazyListState()
    val items = state.items
    val rows = remember(items, foldTurns) { if (foldTurns) TurnFolding.fold(items) else items.map { ChatRowModel.Item(it) } }
    val haptic = rememberHaptic()
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val chatPrefs = com.huanmeng.huanhermes.ui.chat.LocalChatPrefs.current
    val attachments by vm.attachments.collectAsStateWithLifecycle()
    val notice by vm.notice.collectAsStateWithLifecycle()
    val goal by vm.goal.collectAsStateWithLifecycle()
    var attachSheet by remember { mutableStateOf(false) }
    var goalDialog by remember { mutableStateOf(false) }
    var scheduleDialog by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    var pendingPaste by remember { mutableStateOf<String?>(null) }
    // Attachments (F1): camera to a cache file, gallery, any file, clipboard image.
    val cameraFile = remember { java.io.File(ctx.cacheDir, "camera").apply { mkdirs() }.let { java.io.File(it, "shot.jpg") } }
    val cameraUri = remember { androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".files", cameraFile) }
    val takePhoto = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.TakePicture()) { ok ->
        if (ok) vm.addAttachmentFrom(cameraUri, "photo-${System.currentTimeMillis() / 1000}.jpg")
    }
    // The manifest declares CAMERA (QR pairing), so the capture intent needs the grant too.
    val cameraPerm = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) runCatching { takePhoto.launch(cameraUri) } else android.widget.Toast.makeText(ctx, "需要相机权限才能拍照", android.widget.Toast.LENGTH_SHORT).show()
    }
    val pickImage = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let { vm.addAttachmentFrom(it) }
    }
    val pickFile = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { vm.addAttachmentFrom(it) }
    }
    val clipboardImage: android.net.Uri? = remember(attachSheet) {
        runCatching {
            val cm = ctx.getSystemService(android.content.ClipboardManager::class.java)
            val clip = cm?.primaryClip
            if (clip != null && clip.description.hasMimeType("image/*")) clip.getItemAt(0)?.uri else null
        }.getOrNull()
    }
    // Read replies aloud (F3).
    var tts by remember { mutableStateOf<android.speech.tts.TextToSpeech?>(null) }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { tts?.shutdown() } }
    val speak: (String) -> Unit = { text ->
        val say = com.huanmeng.huanhermes.ui.chat.speakable(text)
        val engine = tts
        if (engine != null) engine.speak(say, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, "reply")
        else {
            var created: android.speech.tts.TextToSpeech? = null
            created = android.speech.tts.TextToSpeech(ctx) { status ->
                if (status == android.speech.tts.TextToSpeech.SUCCESS) {
                    created?.language = java.util.Locale.getDefault()
                    created?.speak(say, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, "reply")
                }
            }
            tts = created
        }
    }
    LaunchedEffect(notice) {
        notice?.let { android.widget.Toast.makeText(ctx, it, android.widget.Toast.LENGTH_SHORT).show(); vm.clearNotice() }
    }
    val deviceAuth = com.huanmeng.huanhermes.ui.rememberDeviceAuth()
    // Stall hint (D2): re-check every 30 s while a run is active.
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    var stallDismissedAt by rememberSaveable { mutableStateOf(0L) }
    LaunchedEffect(state.runActive) {
        while (state.runActive) { now = System.currentTimeMillis(); kotlinx.coroutines.delay(30_000) }
    }
    // In-chat search (A6).
    var searching by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    var matchAt by rememberSaveable { mutableStateOf(0) }
    val matches = remember(items, query) { com.huanmeng.huanhermes.core.chat.TranscriptSearch.matches(items, query) }
    fun rowOf(id: Long) = rows.indexOfFirst { r ->
        when (r) { is ChatRowModel.Item -> r.item.id == id; is ChatRowModel.FoldedWork -> r.children.any { it.id == id } }
    }
    // Files each finished turn changed (B1), keyed by its RunEnded id.
    val turnFiles = remember(items) {
        val out = HashMap<Long, List<com.huanmeng.huanhermes.core.chat.ChangedFiles.File>>()
        var start = 0
        items.forEachIndexed { i, it ->
            if (it is ChatItem.User) start = i + 1
            if (it is ChatItem.RunEnded) {
                val files = com.huanmeng.huanhermes.core.chat.ChangedFiles.of(items.subList(start.coerceAtMost(i), i))
                if (files.isNotEmpty()) out[it.id] = files
                start = i + 1
            }
        }
        out
    }
    // Voice input through the system recogniser (A5), only when one is installed.
    val canVoice = remember {
        android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH).resolveActivity(ctx.packageManager) != null
    }
    val voice = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { r ->
        val heard = r.data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
        if (!heard.isNullOrBlank()) { input = if (input.isBlank()) heard else "$input $heard"; vm.saveDraft(input) }
    }

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
    LaunchedEffect(rows.size, items.lastOrNull(), viewport) {
        if (rows.isNotEmpty() && stick) list.scrollToItem(rows.size - 1, 100_000) // offset is clamped to the end
    }
    // Rows also grow without the items changing (Markdown parsed off-thread, code
    // highlighted, cards expanding): follow the bottom edge of the last row too.
    LaunchedEffect(list) {
        snapshotFlow {
            val last = list.layoutInfo.visibleItemsInfo.lastOrNull()
            if (last == null) 0L else (last.index.toLong() shl 32) + last.offset + last.size
        }.collect {
            val n = list.layoutInfo.totalItemsCount
            if (stick && n > 0 && !list.isScrollInProgress && list.canScrollForward) list.scrollToItem(n - 1, 100_000)
        }
    }

    Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
        TopAppBar(
            title = {
                Column {
                    Text(vm.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val sub = listOfNotNull(
                        if (state.typing) "正在输入…" else if (state.runActive) "运行中" else null,
                        state.model, state.mode,
                    ).joinToString(" · ")
                    if (sub.isNotEmpty()) Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
            },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
            actions = {
                IconButton(onClick = { searching = !searching; if (!searching) query = "" }) { Icon(Icons.Outlined.Search, "在会话中搜索") }
                IconButton(onClick = {
                    val md = com.huanmeng.huanhermes.core.chat.TranscriptExport.markdown(vm.title, items, vm.hostLabel)
                    val send = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/markdown")
                        .putExtra(android.content.Intent.EXTRA_SUBJECT, com.huanmeng.huanhermes.core.chat.TranscriptExport.fileName(vm.title))
                        .putExtra(android.content.Intent.EXTRA_TEXT, md)
                    runCatching { ctx.startActivity(android.content.Intent.createChooser(send, "导出会话为 Markdown")) }
                }, enabled = items.isNotEmpty()) { Icon(Icons.Outlined.IosShare, "导出会话") }
                Box {
                    IconButton(onClick = { moreMenu = true }) { Icon(Icons.Outlined.MoreVert, "更多") }
                    androidx.compose.material3.DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                        androidx.compose.material3.DropdownMenuItem(text = { Text("设定会话目标") }, onClick = { moreMenu = false; goalDialog = true })
                        androidx.compose.material3.DropdownMenuItem(text = { Text("定时发送…") }, onClick = { moreMenu = false; scheduleDialog = true })
                        androidx.compose.material3.DropdownMenuItem(text = { Text("重新加载记录") }, onClick = { moreMenu = false; vm.reload() })
                        androidx.compose.material3.DropdownMenuItem(text = { Text("连接诊断") }, onClick = { moreMenu = false; showDiagnostics = true })
                    }
                }
            },
        )
        if (searching) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = query, onValueChange = { query = it; matchAt = 0 },
                    modifier = Modifier.weight(1f).testTag("chat-search"), singleLine = true,
                    placeholder = { Text("搜索消息与工具输出") },
                )
                Text(if (matches.isEmpty()) "0" else "${matchAt + 1}/${matches.size}", Modifier.padding(horizontal = 8.dp), style = MaterialTheme.typography.labelMedium)
                fun jump(delta: Int) {
                    if (matches.isEmpty()) return
                    matchAt = (matchAt + delta + matches.size) % matches.size
                    val idx = rowOf(matches[matchAt])
                    if (idx >= 0) { stick = false; scope.launch { list.animateScrollToItem(idx) } }
                }
                IconButton(onClick = { jump(-1) }, enabled = matches.isNotEmpty()) { Icon(Icons.Outlined.KeyboardArrowUp, "上一个结果") }
                IconButton(onClick = { jump(1) }, enabled = matches.isNotEmpty()) { Icon(Icons.Outlined.KeyboardArrowDown, "下一个结果") }
            }
            LaunchedEffect(matches) {
                if (matches.isNotEmpty()) { val idx = rowOf(matches[matchAt.coerceIn(0, matches.lastIndex)]); if (idx >= 0) { stick = false; list.animateScrollToItem(idx) } }
            }
        }
        goal?.let { g ->
            com.huanmeng.huanhermes.ui.chat.GoalStrip(
                g, onEdit = { goalDialog = true },
                onSend = { haptic.tick(); vm.sendNow("当前目标：$g"); stick = true },
                onClear = { vm.setGoal(null) },
            )
        }
        HealthStrip(state.banner, onRetry = vm::reconnect, onDiagnose = { showDiagnostics = true })
        if (state.reloading) LinearProgressIndicator(Modifier.fillMaxWidth())
        vm.safeError(state.error)?.let {
            Text(it, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (items.isEmpty() && !state.reloading) ChatEmpty(onPick = { input = it })
            LazyColumn(
                state = list,
                modifier = Modifier.fillMaxSize().testTag("chat-list"),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                itemsIndexed(rows, key = { _, it -> it.key }) { i, row ->
                    when (row) {
                        is ChatRowModel.Item -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            ChatRow(
                                row.item, live = state.runActive && i == rows.lastIndex,
                                onDecision = { d ->
                                    val perm = row.item as ChatItem.Permission
                                    if (d == "allow_all" && chatPrefs.confirmAllowAll) deviceAuth("确认允许本会话内的同类操作") { haptic.confirm(); vm.respond(perm, d) }
                                    else { haptic.confirm(); vm.respond(perm, d) }
                                },
                                onAnswer = { d, text, answers -> haptic.confirm(); vm.respond(row.item as ChatItem.Permission, d, text, answers) },
                                onSpeak = speak,
                                onQuote = { t -> input = com.huanmeng.huanhermes.core.chat.Quote.insert(input, t); vm.saveDraft(input) },
                                onEdit = { t -> input = t; vm.saveDraft(input) },
                            )
                            turnFiles[row.item.id]?.let { files -> ChangedFilesCard(files, onOpen = { p -> onOpenDiff(p, vm.project) }) }
                        }
                        is ChatRowModel.FoldedWork -> FoldedWorkRow(row)
                    }
                }
            }
            // Scrolled up to read: jump between my messages, or one tap back to the newest.
            if (!stick && rows.isNotEmpty()) {
                Column(Modifier.align(Alignment.BottomEnd).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SmallFloatingActionButton(onClick = {
                        val first = list.firstVisibleItemIndex
                        val prev = rows.indices.lastOrNull { it < first && (rows[it] as? ChatRowModel.Item)?.item is ChatItem.User }
                        scope.launch { list.animateScrollToItem(prev ?: 0) }
                    }) { Icon(Icons.Outlined.KeyboardDoubleArrowUp, "上一条我的消息") }
                    SmallFloatingActionButton(onClick = {
                        val first = list.firstVisibleItemIndex
                        val next = rows.indices.firstOrNull { it > first && (rows[it] as? ChatRowModel.Item)?.item is ChatItem.User }
                        if (next != null) scope.launch { list.animateScrollToItem(next) }
                        else { stick = true; scope.launch { list.animateScrollToItem(rows.size - 1, 100_000) } }
                    }) { Icon(Icons.Outlined.KeyboardDoubleArrowDown, "下一条我的消息") }
                    SmallFloatingActionButton(
                        onClick = { stick = true; scope.launch { list.animateScrollToItem(rows.size - 1, 100_000) } },
                    ) { Icon(Icons.Outlined.KeyboardArrowDown, "回到最新消息") }
                }
            }
        }
        if (state.stalled(now) && state.lastActivityAt > stallDismissedAt) {
            Surface(color = MaterialTheme.colorScheme.tertiaryContainer, modifier = Modifier.fillMaxWidth().testTag("stall-strip")) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("已 ${(now - state.lastActivityAt) / 60_000} 分钟没有新输出，可能卡住了", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                    TextButton(onClick = { stallDismissedAt = state.lastActivityAt }) { Text("继续等") }
                    TextButton(onClick = vm::cancel) { Text("中断") }
                }
            }
        }
        state.usage?.let { u ->
            val pct = u.contextPercent
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 2.dp).testTag("usage-row"), verticalAlignment = Alignment.CenterVertically) {
                if (pct != null) androidx.compose.material3.LinearProgressIndicator(
                    progress = { pct / 100f }, modifier = Modifier.width(56.dp),
                    color = if (pct >= 80) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                )
                Text(
                    listOfNotNull(pct?.let { "上下文 $it%" }, u.totalTokens?.let { "${formatTokens(it)} tokens" }, u.costUsd?.let { "$" + String.format(java.util.Locale.US, "%.2f", it) })
                        .joinToString(" · ") + if ((pct ?: 0) >= 80) " · 可用 /compact 压缩" else "",
                    Modifier.padding(start = 8.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        RunQueue(
            state.runQueue,
            onEdit = { id -> vm.takeQueued(id)?.let { input = it } },
            onSendNow = { id -> vm.sendQueuedNow(id) },
            onRemove = { id -> vm.takeQueued(id) },
        )
        SlashPalette(input, onPick = { cmd -> input = cmd.command + if (cmd.takesArgument) " " else "" })
        MentionPalette(
            visible = com.huanmeng.huanhermes.core.chat.Mentions.activeQuery(input) != null,
            files = fileHits,
            onPick = { path -> input = com.huanmeng.huanhermes.core.chat.Mentions.insert(input, path); vm.onInputChanged(input); vm.saveDraft(input) },
        )
        com.huanmeng.huanhermes.ui.chat.AttachmentStrip(attachments, onRemove = vm::removeAttachment)
        Composer(
            input = input,
            onInput = { next ->
                // A big paste becomes an attachment if the user wants (F2).
                if (next.length - input.length > 3000 && next.startsWith(input.take(0))) pendingPaste = next
                else { input = next; vm.saveDraft(next); vm.onInputChanged(next) }
            },
            onAttach = { attachSheet = true },
            attachCount = attachments.size,
            connected = state.connected,
            runActive = state.runActive,
            queues = vm.queuesWhileRunning(),
            model = state.model, mode = state.mode, models = models,
            history = history,
            onSend = {
                val text = input
                if (text.isNotBlank() || attachments.isNotEmpty()) {
                    haptic.tick()
                    vm.sendAll(text) { ok -> if (ok) { input = ""; stick = true } }
                }
            },
            onCommand = { cmd -> haptic.tick(); vm.sendNow(cmd); stick = true },
            onCancel = vm::cancel,
            onVoice = if (canVoice) ({
                val i = android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    .putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "说出要发给 Agent 的话")
                runCatching { voice.launch(i) }
                Unit
            }) else null,
        )
    }

    if (attachSheet) com.huanmeng.huanhermes.ui.chat.AttachSheet(
        onCamera = {
            if (androidx.core.content.ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED)
                runCatching { takePhoto.launch(cameraUri) }
            else cameraPerm.launch(android.Manifest.permission.CAMERA)
        },
        onGallery = { pickImage.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        onFile = { pickFile.launch(arrayOf("*/*")) },
        onClipboard = clipboardImage?.let { uri -> { vm.addAttachmentFrom(uri); Unit } },
        onDismiss = { attachSheet = false },
    )
    pendingPaste?.let { pasted ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { pendingPaste = null },
            title = { Text("粘贴了 ${pasted.length - input.length} 个字") },
            text = { Text("长文本作为附件发送，Agent 读起来更完整，输入框也更清爽。") },
            confirmButton = {
                TextButton(onClick = {
                    val added = pastedPart(input, pasted)
                    vm.addAttachment(com.huanmeng.huanhermes.core.protocol.Attachment("pasted-${System.currentTimeMillis() / 1000}.txt", "text/plain", added.toByteArray()))
                    pendingPaste = null
                }) { Text("转为附件") }
            },
            dismissButton = { TextButton(onClick = { input = pasted; vm.saveDraft(pasted); vm.onInputChanged(pasted); pendingPaste = null }) { Text("直接粘贴") } },
        )
    }
    if (goalDialog) com.huanmeng.huanhermes.ui.chat.GoalDialog(goal.orEmpty(), onSave = { vm.setGoal(it); goalDialog = false }, onDismiss = { goalDialog = false })
    if (scheduleDialog) com.huanmeng.huanhermes.ui.chat.ScheduleDialog(
        input, onSave = { p, h, m, every -> vm.schedulePrompt(p, h, m, every); scheduleDialog = false }, onDismiss = { scheduleDialog = false },
    )
    if (showDiagnostics) DiagnosticsSheet(
        bridgeConnected = state.connected,
        capabilities = state.hostCapabilities,
        lastError = vm.safeError(state.error),
        report = { vm.diagnostics() },
        onReconnect = vm::reconnect,
        onDismiss = { showDiagnostics = false },
    )
}

@Composable
private fun ChatRow(
    item: ChatItem,
    live: Boolean,
    onDecision: (String) -> Unit,
    onQuote: (String) -> Unit = {},
    onEdit: (String) -> Unit = {},
    onAnswer: (String, String?, Map<String, List<String>>?) -> Unit = { d, _, _ -> onDecision(d) },
    onSpeak: (String) -> Unit = {},
) {
    when (item) {
        is ChatItem.User -> MessageActions(item.text, onQuote = { onQuote(item.text) }, onEdit = { onEdit(item.text) }) {
            Bubble(alignEnd = true, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Column {
                    Text(item.text, color = MaterialTheme.colorScheme.onSurface)
                    if (item.queued) Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Schedule, null, Modifier.padding(end = 4.dp))
                        Text("等待发送（离线队列）", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
        // Agent replies read like a document (full width, Markdown), not a chat bubble.
        is ChatItem.Assistant -> MessageActions(item.text, onQuote = { onQuote(item.text) }, onSpeak = { onSpeak(item.text) }) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 2.dp)) {
                MarkdownView(item.text)
                if (item.streaming) Text("▍", color = MaterialTheme.colorScheme.primary)
                else com.huanmeng.huanhermes.ui.chat.MessageActionBar(item.text, onQuote = { onQuote(item.text) }, onSpeak = { onSpeak(item.text) })
            }
        }
        is ChatItem.Thinking -> ThinkingRow(item, live)
        is ChatItem.Tool -> ToolRow(item)
        is ChatItem.Permission -> when (item.kind) {
            "plan" -> com.huanmeng.huanhermes.ui.chat.PlanCard(item, onAnswer)
            "question" -> com.huanmeng.huanhermes.ui.chat.QuestionCard(item, onAnswer)
            else -> PermissionCard(item, onDecision)
        }
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
                .background(color, if (alignEnd) RoundedCornerShape(20.dp, 6.dp, 20.dp, 20.dp) else RoundedCornerShape(6.dp, 20.dp, 20.dp, 20.dp))
                .padding(horizontal = 14.dp, vertical = 10.dp),
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
    val decided = item.decision
    val tint = when (decided) { null -> Brand.warning; "deny" -> MaterialTheme.colorScheme.error; else -> Brand.success }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    when (decided) { null -> Icons.Outlined.Schedule; "deny" -> Icons.Outlined.ErrorOutline; else -> Icons.Outlined.CheckCircle },
                    null, Modifier.size(18.dp), tint = tint,
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    when (decided) { null -> "需要权限 · 待处理"; "deny" -> "需要权限 · 已拒绝"; "allow_all" -> "需要权限 · 本会话已允许"; else -> "需要权限 · 已允许" },
                    style = MaterialTheme.typography.titleSmall, color = tint,
                )
            }
            MarkdownView(item.text, style = MaterialTheme.typography.bodyMedium)
            if (decided == null) {
                PermissionButtons(item.buttons.map { it.data }, onDecision)
                // Non-permission buttons (plain actions) are offered with their own labels.
                val others = item.buttons.filterNot { b -> listOf("allow", "allow_all", "deny").any { b.data.endsWith(":$it") } }
                others.forEach { b -> TextButton(onClick = { onDecision(b.data) }) { Text(b.text) } }
            }
        }
    }
}

/** "本轮改动" card under a finished turn: tap a file to open its diff. */
@Composable
private fun ChangedFilesCard(files: List<com.huanmeng.huanhermes.core.chat.ChangedFiles.File>, onOpen: (String?) -> Unit) {
    androidx.compose.material3.OutlinedCard(Modifier.fillMaxWidth().testTag("changed-files")) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("本轮改动 ${files.size} 个文件", Modifier.weight(1f), style = MaterialTheme.typography.labelLarge)
                TextButton(onClick = { onOpen(null) }) { Text("查看改动") }
            }
            files.take(8).forEach { f ->
                Row(
                    Modifier.fillMaxWidth().clickable { onOpen(f.path) }.padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Outlined.Description, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                    Text(f.path, Modifier.weight(1f).padding(horizontal = 8.dp), style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(f.kind + if (f.edits > 1) " ×${f.edits}" else "", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (files.size > 8) Text("还有 ${files.size - 8} 个…", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun formatTokens(n: Long): String = when {
    n >= 1_000_000 -> String.format(java.util.Locale.US, "%.1fM", n / 1_000_000.0)
    n >= 1_000 -> String.format(java.util.Locale.US, "%.1fk", n / 1_000.0)
    else -> n.toString()
}

/** The text a paste inserted: [after] minus the common prefix and suffix with [before]. */
private fun pastedPart(before: String, after: String): String {
    var p = 0
    while (p < before.length && p < after.length && before[p] == after[p]) p++
    var s = 0
    while (s < before.length - p && s < after.length - p && before[before.length - 1 - s] == after[after.length - 1 - s]) s++
    return after.substring(p, after.length - s)
}
