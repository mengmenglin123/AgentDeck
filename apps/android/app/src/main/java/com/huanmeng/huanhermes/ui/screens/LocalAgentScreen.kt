package com.huanmeng.huanhermes.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.HourglassTop
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.huanmeng.huanhermes.core.agent.AgentMessage
import com.huanmeng.huanhermes.core.agent.ApprovalPolicy
import com.huanmeng.huanhermes.core.agent.LlmProvider
import com.huanmeng.huanhermes.core.agent.LlmSettings
import com.huanmeng.huanhermes.core.agent.SshServer
import com.huanmeng.huanhermes.core.agent.ToolActivity
import com.huanmeng.huanhermes.core.agent.llmClientFor
import com.huanmeng.huanhermes.core.ssh.TrileadSshRunner
import com.huanmeng.huanhermes.data.LocalAgentController
import com.huanmeng.huanhermes.data.LocalAgentSettings
import com.huanmeng.huanhermes.ui.chat.MarkdownView
import com.huanmeng.huanhermes.ui.pairing.HostKeyPrompt
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.Color
import com.huanmeng.huanhermes.core.agent.AgentTools
import com.huanmeng.huanhermes.core.agent.ConversationMeta
import com.huanmeng.huanhermes.ui.components.Design
import com.huanmeng.huanhermes.ui.components.IconBadge
import com.huanmeng.huanhermes.ui.components.PrefItem
import com.huanmeng.huanhermes.ui.components.SettingsGroup
import com.huanmeng.huanhermes.ui.components.SoftCard
import com.huanmeng.huanhermes.ui.components.Tag
import com.huanmeng.huanhermes.ui.components.Tint
import com.huanmeng.huanhermes.ui.components.groupShape
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

class LocalAgentViewModel(val ctl: LocalAgentController) : ViewModel() {
    val prompt = MutableStateFlow<HostKeyPrompt?>(null)
    val toast = MutableStateFlow<String?>(null)
    val testing = MutableStateFlow<String?>(null)

    init { ctl.ensureLoaded() }

    fun save(s: SshServer, onOk: () -> Unit) = viewModelScope.launch {
        val err = ctl.servers.upsert(s)
        if (err == null) { onOk(); toast.value = "已保存 ${s.name.trim()}" } else toast.value = err
    }

    fun remove(s: SshServer) = viewModelScope.launch { ctl.servers.remove(s.id); toast.value = "已删除 ${s.name}" }

    /** Connects with trust-on-first-use, stores the confirmed fingerprint, runs `uname -a`. */
    fun test(s: SshServer) = viewModelScope.launch {
        testing.value = s.id
        try {
            var confirmed = s.hostKey
            val out = withContext(Dispatchers.IO) {
                TrileadSshRunner(s.target(), { alg, fp ->
                    if (fp == s.hostKey) true else {
                        val answer = CompletableDeferred<Boolean>()
                        prompt.value = HostKeyPrompt(s.host, alg, fp, s.hostKey.ifBlank { null }, answer)
                        val ok = runBlocking { answer.await() }
                        prompt.value = null
                        if (ok) confirmed = fp
                        ok
                    }
                }).use { it.run("uname -sr 2>/dev/null || echo connected", 20_000) }
            }
            if (confirmed != s.hostKey) ctl.servers.upsert(s.copy(hostKey = confirmed))
            toast.value = "连接成功：" + out.stdout.trim().ifEmpty { "退出码 ${out.exitCode}" }.take(80)
        } catch (e: Exception) {
            toast.value = e.message ?: e.javaClass.simpleName
        } finally {
            testing.value = null
        }
    }

    fun answer(ok: Boolean) { prompt.value?.answer?.complete(ok) }

    fun testModel(s: LlmSettings) = viewModelScope.launch {
        testing.value = "llm"
        toast.value = try {
            val http = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
            val t = llmClientFor(s, http).complete("只回复 OK。", listOf(AgentMessage.User("ping")), emptyList())
            "模型可用：" + t.text.trim().take(40).ifEmpty { "（空回复）" }
        } catch (e: Exception) { e.message ?: e.javaClass.simpleName } finally { testing.value = null }
    }
}

private enum class AgentPage { Chat, Servers, Model }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocalAgentScreen(vm: LocalAgentViewModel, onBack: () -> Unit) {
    val ctl = vm.ctl
    val settings by ctl.settings.collectAsStateWithLifecycle()
    val servers by ctl.servers.servers.collectAsStateWithLifecycle()
    val toast by vm.toast.collectAsStateWithLifecycle()
    val prompt by vm.prompt.collectAsStateWithLifecycle()
    val convs by ctl.conversations.list.collectAsStateWithLifecycle()
    val currentId by ctl.agent.conversationId.collectAsStateWithLifecycle()
    val running by ctl.agent.running.collectAsStateWithLifecycle()
    val ctx = androidx.compose.ui.platform.LocalContext.current
    var page by rememberSaveable { mutableStateOf(AgentPage.Chat) }
    var editing by remember { mutableStateOf<SshServer?>(null) }
    val drawer = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    LaunchedEffect(toast) { toast?.let { android.widget.Toast.makeText(ctx, it, android.widget.Toast.LENGTH_SHORT).show(); vm.toast.value = null } }
    androidx.activity.compose.BackHandler(enabled = page != AgentPage.Chat || drawer.isOpen) {
        if (drawer.isOpen) scope.launch { drawer.close() } else page = AgentPage.Chat
    }

    ModalNavigationDrawer(
        drawerState = drawer, gesturesEnabled = page == AgentPage.Chat,
        drawerContent = {
            ConversationDrawer(
                convs, currentId, running, serverCount = servers.size, model = settings.llm.effectiveModel,
                onNew = { ctl.newConversation(); scope.launch { drawer.close() } },
                onOpen = { ctl.open(it); scope.launch { drawer.close() } },
                onDelete = ctl::delete, onRename = ctl::rename,
                onServers = { page = AgentPage.Servers; scope.launch { drawer.close() } },
                onModel = { page = AgentPage.Model; scope.launch { drawer.close() } },
            )
        },
    ) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.surface,
            topBar = {
                TopAppBar(
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
                    title = {
                        when (page) {
                            AgentPage.Chat -> Column {
                                Text(convs.firstOrNull { it.id == currentId }?.title ?: "本地 Agent", maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
                                Text(if (settings.llm.configured) settings.llm.effectiveModel.uppercase() else "未配置模型", style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            AgentPage.Servers -> Text("SSH 服务器")
                            AgentPage.Model -> Text("模型与审批")
                        }
                    },
                    navigationIcon = {
                        if (page == AgentPage.Chat) Row {
                            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") }
                        } else IconButton(onClick = { page = AgentPage.Chat }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回对话") }
                    },
                    actions = {
                        if (page == AgentPage.Chat) {
                            IconButton(onClick = { scope.launch { drawer.open() } }, Modifier.testTag("agent-drawer")) { Icon(Icons.AutoMirrored.Outlined.List, "对话列表") }
                            IconButton(onClick = { ctl.newConversation() }, enabled = !running, modifier = Modifier.testTag("agent-new")) { Icon(Icons.Outlined.AddComment, "新对话") }
                        }
                        if (page == AgentPage.Servers) IconButton(onClick = { editing = SshServer(name = "", host = "", username = "") }, Modifier.testTag("agent-add-server")) {
                            Icon(Icons.Outlined.Add, "添加服务器")
                        }
                    },
                )
            },
        ) { pad ->
            Box(Modifier.padding(pad).fillMaxSize()) {
                when (page) {
                    AgentPage.Chat -> AgentChat(ctl, settings, servers.size, onServers = { page = AgentPage.Servers }, onModel = { page = AgentPage.Model })
                    AgentPage.Servers -> ServerList(servers, vm, onEdit = { editing = it }, onAdd = { editing = SshServer(name = "", host = "", username = "") })
                    AgentPage.Model -> ModelSettings(settings, vm, onSave = { ctl.saveSettings(it); vm.toast.value = "已保存"; page = AgentPage.Chat })
                }
            }
        }
    }
    editing?.let { s -> ServerDialog(s, onSave = { vm.save(it) { editing = null } }, onDismiss = { editing = null }) }
    prompt?.let { p ->
        AlertDialog(
            onDismissRequest = {},
            icon = { Icon(Icons.Outlined.Fingerprint, null) },
            title = { Text(if (p.previous == null) "确认主机指纹" else "主机指纹已变化！") },
            text = {
                Column {
                    Text(if (p.previous == null) "第一次连接 ${p.host}，请和服务器上 ssh-keygen -lf 的结果核对 ${p.algorithm} 指纹：" else "${p.host} 的指纹和上次不同，可能重装过系统，也可能被劫持。上次：${p.previous}")
                    Spacer(Modifier.size(8.dp))
                    Text(p.fingerprint, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
                }
            },
            confirmButton = { TextButton(onClick = { vm.answer(true) }, Modifier.testTag("agent-trust")) { Text("信任") } },
            dismissButton = { TextButton(onClick = { vm.answer(false) }) { Text("取消") } },
        )
    }
}

@Composable
private fun ConversationDrawer(
    convs: List<ConversationMeta>, currentId: String?, running: Boolean, serverCount: Int, model: String,
    onNew: () -> Unit, onOpen: (String) -> Unit, onDelete: (String) -> Unit, onRename: (String, String) -> Unit,
    onServers: () -> Unit, onModel: () -> Unit,
) {
    var menuFor by remember { mutableStateOf<String?>(null) }
    var renaming by remember { mutableStateOf<ConversationMeta?>(null) }
    ModalDrawerSheet(Modifier.width(320.dp), drawerContainerColor = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.fillMaxSize().padding(horizontal = 12.dp)) {
            Text("本地 Agent", Modifier.padding(start = 12.dp, top = 20.dp, bottom = 12.dp), style = MaterialTheme.typography.titleLarge)
            Surface(onClick = onNew, enabled = !running, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.primaryContainer, modifier = Modifier.fillMaxWidth().testTag("drawer-new")) {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.AddComment, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                    Spacer(Modifier.width(12.dp))
                    Text("新对话", color = MaterialTheme.colorScheme.onPrimaryContainer, style = MaterialTheme.typography.titleSmall)
                }
            }
            Text("最近", Modifier.padding(start = 12.dp, top = 18.dp, bottom = 6.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            LazyColumn(Modifier.weight(1f).testTag("agent-conversations"), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (convs.isEmpty()) item { Text("还没有对话", Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                items(convs, key = { it.id }) { c ->
                    val selected = c.id == currentId
                    Box {
                        Surface(
                            onClick = { if (!running) onOpen(c.id) }, shape = RoundedCornerShape(14.dp),
                            color = if (selected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent, modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(Modifier.padding(start = 14.dp, top = 10.dp, bottom = 10.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(c.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
                                    Text(relativeTime(c.updatedAt) + " · ${c.messages} 条", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                IconButton(onClick = { menuFor = c.id }, Modifier.size(36.dp)) { Icon(Icons.Outlined.MoreVert, "对话操作", Modifier.size(18.dp)) }
                            }
                        }
                        DropdownMenu(expanded = menuFor == c.id, onDismissRequest = { menuFor = null }) {
                            DropdownMenuItem(text = { Text("重命名") }, leadingIcon = { Icon(Icons.Outlined.Edit, null) }, onClick = { menuFor = null; renaming = c })
                            DropdownMenuItem(text = { Text("删除") }, leadingIcon = { Icon(Icons.Outlined.Delete, null) }, onClick = { menuFor = null; onDelete(c.id) },
                                enabled = !(running && selected))
                        }
                    }
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            DrawerEntry(Icons.Outlined.Dns, "SSH 服务器", "$serverCount 台", onServers)
            DrawerEntry(Icons.Outlined.Tune, "模型与审批", model, onModel)
            Spacer(Modifier.height(12.dp))
        }
    }
    renaming?.let { c ->
        var t by remember { mutableStateOf(c.title) }
        AlertDialog(
            onDismissRequest = { renaming = null }, title = { Text("重命名对话") },
            text = { OutlinedTextField(t, { t = it.take(60) }, singleLine = true, modifier = Modifier.fillMaxWidth()) },
            confirmButton = { TextButton(onClick = { onRename(c.id, t); renaming = null }) { Text("保存") } },
            dismissButton = { TextButton(onClick = { renaming = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun DrawerEntry(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, sub: String, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(14.dp), color = Color.Transparent, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            IconBadge(icon, Tint.Secondary, 36.dp)
            Spacer(Modifier.width(12.dp))
            Column {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(sub, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

private fun relativeTime(t: Long): String {
    val d = (System.currentTimeMillis() - t) / 1000
    return when {
        d < 60 -> "刚刚"
        d < 3600 -> "${d / 60} 分钟前"
        d < 86_400 -> "${d / 3600} 小时前"
        d < 7 * 86_400 -> "${d / 86_400} 天前"
        else -> java.text.SimpleDateFormat("M月d日", java.util.Locale.CHINA).format(java.util.Date(t))
    }
}

private sealed class AgentRow(val key: String) {
    class User(key: String, val text: String) : AgentRow(key)
    class Reply(key: String, val text: String, val showHeader: Boolean) : AgentRow(key)
    class Tool(key: String, val callId: String) : AgentRow(key)
}

@Composable
private fun AgentChat(ctl: LocalAgentController, settings: LocalAgentSettings, serverCount: Int, onServers: () -> Unit, onModel: () -> Unit) {
    val messages by ctl.agent.messages.collectAsStateWithLifecycle()
    val activities by ctl.agent.activities.collectAsStateWithLifecycle()
    val running by ctl.agent.running.collectAsStateWithLifecycle()
    val streaming by ctl.agent.streaming.collectAsStateWithLifecycle()
    val error by ctl.agent.error.collectAsStateWithLifecycle()
    val approval by ctl.agent.approval.collectAsStateWithLifecycle()
    var input by rememberSaveable { mutableStateOf("") }
    val list = rememberLazyListState()
    val rows = remember(messages) {
        var lastWasUser = true
        messages.flatMapIndexed { i, m ->
            when (m) {
                is AgentMessage.User -> { lastWasUser = true; listOf<AgentRow>(AgentRow.User("u$i", m.text)) }
                is AgentMessage.Assistant -> buildList<AgentRow> {
                    if (m.text.isNotBlank()) { add(AgentRow.Reply("a$i", m.text, lastWasUser)); lastWasUser = false }
                    m.toolCalls.forEach { add(AgentRow.Tool("t$i-${it.id}", it.id)); lastWasUser = false }
                }
                is AgentMessage.ToolResult -> emptyList()
            }
        }
    }
    LaunchedEffect(rows.size, activities.size, running, streaming?.length?.div(80)) { if (rows.isNotEmpty() || streaming != null) list.scrollToItem(rows.size + 2) }
    Column(Modifier.fillMaxSize().imePadding()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth().testTag("agent-list"), state = list,
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (rows.isEmpty() && streaming == null) item { AgentEmpty(settings.llm.configured, serverCount, onServers, onModel) { input = it } }
            items(rows, key = { it.key }) { r ->
                when (r) {
                    is AgentRow.User -> Row(Modifier.fillMaxWidth()) {
                        Spacer(Modifier.weight(1f).widthIn(min = 48.dp))
                        Surface(shape = RoundedCornerShape(20.dp, 6.dp, 20.dp, 20.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                            SelectionContainer { Text(r.text, Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) }
                        }
                    }
                    is AgentRow.Tool -> activities[r.callId]?.let { a ->
                        ToolCard(a, waiting = approval?.activity?.callId == a.callId, onAnswer = ctl.agent::answerApproval)
                    }
                    is AgentRow.Reply -> Column(Modifier.fillMaxWidth()) {
                        if (r.showHeader) AgentHeader(settings.llm.effectiveModel)
                        SelectionContainer { MarkdownView(r.text, Modifier.fillMaxWidth().testTag("agent-reply"), MaterialTheme.typography.bodyLarge) }
                        com.huanmeng.huanhermes.ui.chat.MessageActionBar(r.text)
                    }
                }
            }
            streaming?.let { s ->
                item(key = "streaming") {
                    Column(Modifier.fillMaxWidth()) {
                        if (rows.lastOrNull() is AgentRow.User) AgentHeader(settings.llm.effectiveModel)
                        if (s.isEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp))
                            Text("思考中…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        } else {
                            MarkdownView(s + " ▍", Modifier.fillMaxWidth().testTag("agent-streaming"), MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
            error?.let { e ->
                item(key = "error") {
                    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth().testTag("agent-error")) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.ErrorOutline, null, tint = MaterialTheme.colorScheme.onErrorContainer)
                            Spacer(Modifier.width(10.dp))
                            Text(e, color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
            item(key = "end") { Spacer(Modifier.height(4.dp)) }
        }
        AgentComposer(
            input, { input = it }, settings, serverCount, running,
            onSend = { ctl.send(input); input = "" }, onStop = ctl::stop, onServers = onServers,
            onPolicy = { p -> ctl.saveSettings(settings.copy(policy = p)) },
        )
    }
}

@Composable
private fun AgentHeader(model: String) {
    Row(Modifier.padding(bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconBadge(Icons.Outlined.SmartToy, Tint.Tertiary, 26.dp)
        Spacer(Modifier.width(8.dp))
        Text(model.uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun AgentEmpty(configured: Boolean, serverCount: Int, onServers: () -> Unit, onModel: () -> Unit, onPick: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        IconBadge(Icons.Outlined.SmartToy, Tint.Tertiary, 64.dp)
        Spacer(Modifier.height(14.dp))
        Text("用一句话管理你的服务器", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(6.dp))
        Text("Agent 在手机上运行，用你自己的模型 Key，通过 SSH 执行命令、读写文件。", style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp))
        Spacer(Modifier.height(20.dp))
        val setup = buildList<@Composable (androidx.compose.ui.graphics.Shape) -> Unit> {
            if (!configured) add { sh -> PrefItem("配置模型", sh, subtitle = "OpenAI 兼容或 Claude 的 API Key", icon = Icons.Outlined.Key, tint = Tint.Primary, onClick = onModel) }
            if (serverCount == 0) add { sh -> PrefItem("添加 SSH 服务器", sh, subtitle = "密码或私钥，只加密保存在本机", icon = Icons.Outlined.Dns, tint = Tint.Secondary, onClick = onServers) }
        }
        if (setup.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) { setup.forEachIndexed { i, f -> f(groupShape(i, setup.size)) } }
        else {
            val prompts = listOf("看看所有服务器的磁盘和内存", "nginx 为什么起不来？", "最近 1 小时的错误日志", "把系统更新一下")
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                prompts.forEachIndexed { i, p ->
                    Surface(onClick = { onPick(p) }, shape = groupShape(i, prompts.size, 18.dp, 6.dp), color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.AutoAwesome, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.width(10.dp)); Text(p, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AgentComposer(
    input: String, onInput: (String) -> Unit, settings: LocalAgentSettings, serverCount: Int, running: Boolean,
    onSend: () -> Unit, onStop: () -> Unit, onServers: () -> Unit, onPolicy: (ApprovalPolicy) -> Unit,
) {
    var policyMenu by remember { mutableStateOf(false) }
    Surface(shape = RoundedCornerShape(26.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, bottom = 8.dp, top = 4.dp)) {
        Column(Modifier.padding(start = 6.dp, end = 6.dp, top = 2.dp, bottom = 6.dp)) {
            TextField(
                input, onInput, Modifier.fillMaxWidth().heightIn(max = 200.dp).testTag("agent-input"),
                placeholder = { Text(if (settings.llm.configured) "让 Agent 帮你做点什么…" else "请先配置模型") },
                enabled = settings.llm.configured,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent, disabledContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, disabledIndicatorColor = Color.Transparent,
                ),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(onClick = onServers, shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.surfaceContainerHighest) {
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Dns, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(4.dp)); Text("$serverCount 台服务器", style = MaterialTheme.typography.labelMedium)
                    }
                }
                Spacer(Modifier.width(6.dp))
                Box {
                    Surface(onClick = { policyMenu = true }, shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.surfaceContainerHighest, modifier = Modifier.testTag("agent-policy")) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(if (settings.policy == ApprovalPolicy.NEVER) Icons.Outlined.GppMaybe else Icons.Outlined.VerifiedUser, null, Modifier.size(16.dp),
                                tint = if (settings.policy == ApprovalPolicy.NEVER) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.width(4.dp)); Text(settings.policy.label, style = MaterialTheme.typography.labelMedium)
                        }
                    }
                    DropdownMenu(expanded = policyMenu, onDismissRequest = { policyMenu = false }) {
                        ApprovalPolicy.entries.forEach { p ->
                            DropdownMenuItem(
                                text = { Column { Text(p.label); Text(p.desc, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } },
                                leadingIcon = { if (p == settings.policy) Icon(Icons.Outlined.Check, "当前") },
                                onClick = { policyMenu = false; onPolicy(p) },
                            )
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                if (running) FilledIconButton(onClick = onStop, Modifier.testTag("agent-stop"), colors = IconButtonDefaults.filledIconButtonColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer)) {
                    Icon(Icons.Outlined.Stop, "停止")
                } else FilledIconButton(onClick = onSend, enabled = input.isNotBlank() && settings.llm.configured, modifier = Modifier.testTag("agent-send")) {
                    Icon(Icons.Outlined.ArrowUpward, "发送")
                }
            }
        }
    }
}

@Composable
private fun ToolCard(a: ToolActivity, waiting: Boolean, onAnswer: (Boolean) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val c = MaterialTheme.colorScheme
    val (label, tint) = when (a.state) {
        ToolActivity.State.WAITING_APPROVAL -> "等待批准" to Tint.Tertiary
        ToolActivity.State.RUNNING -> "执行中" to Tint.Primary
        ToolActivity.State.DONE -> "完成" to Tint.Secondary
        ToolActivity.State.FAILED -> "失败" to Tint.Error
        ToolActivity.State.DENIED -> "已拒绝" to Tint.Neutral
    }
    val icon = when (a.tool) {
        AgentTools.LIST -> Icons.Outlined.Dns
        AgentTools.READ -> Icons.Outlined.Description
        AgentTools.WRITE -> Icons.Outlined.EditNote
        else -> Icons.Outlined.Terminal
    }
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = if (waiting) c.tertiaryContainer.copy(alpha = 0.55f) else c.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth().animateContentSize().testTag("agent-tool-${a.state.name.lowercase()}"),
    ) {
        Column {
            Row(Modifier.fillMaxWidth().clickable(enabled = a.output.isNotEmpty()) { open = !open }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                if (a.state == ToolActivity.State.RUNNING) Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) }
                else IconBadge(icon, tint, 32.dp)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(a.server ?: "本机", style = MaterialTheme.typography.labelLarge, color = c.primary)
                        Spacer(Modifier.width(6.dp)); Tag(label, tint)
                    }
                    Text(a.summary, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
                        maxLines = if (open || waiting) 12 else 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
                }
                if (a.output.isNotEmpty()) Icon(if (open) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, if (open) "收起输出" else "展开输出", tint = c.onSurfaceVariant)
            }
            if (waiting) Row(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { onAnswer(true) }, Modifier.testTag("agent-approve")) { Icon(Icons.Outlined.Check, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("批准执行") }
                OutlinedButton(onClick = { onAnswer(false) }, Modifier.testTag("agent-deny")) { Text("拒绝") }
            }
            if (open && a.output.isNotEmpty()) Surface(shape = RoundedCornerShape(12.dp), color = c.surfaceContainerHighest, modifier = Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp)) {
                SelectionContainer { Text(a.output.take(20_000), Modifier.padding(10.dp).fillMaxWidth(), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
}

@Composable
private fun ServerList(servers: List<SshServer>, vm: LocalAgentViewModel, onEdit: (SshServer) -> Unit, onAdd: () -> Unit) {
    val testing by vm.testing.collectAsStateWithLifecycle()
    var confirm by remember { mutableStateOf<SshServer?>(null) }
    LazyColumn(Modifier.fillMaxSize().testTag("agent-servers"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Text("Agent 只能操作这里的服务器。密码和私钥用 Android Keystore 加密保存在本机，不会上传。", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp))
        }
        items(servers, key = { it.id }) { s ->
            SoftCard(Modifier.testTag("agent-server-${s.name}")) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconBadge(Icons.Outlined.Dns, if (s.hostKey.isBlank()) Tint.Error else Tint.Primary, 44.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(s.name, style = MaterialTheme.typography.titleMedium)
                        Text(s.label(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, fontFamily = FontFamily.Monospace)
                    }
                }
                Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Tag(if (s.usesKey) "私钥" else "密码", Tint.Secondary)
                    if (s.hostKey.isBlank()) Tag("未确认指纹", Tint.Error) else Tag("指纹 " + s.hostKey.removePrefix("SHA256:").take(10) + "…", Tint.Primary)
                }
                if (s.note.isNotBlank()) Text(s.note, Modifier.padding(top = 8.dp), style = MaterialTheme.typography.bodySmall)
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                    TextButton(onClick = { vm.test(s) }, enabled = testing == null, modifier = Modifier.testTag("agent-test-${s.name}")) {
                        if (testing == s.id) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Icon(Icons.Outlined.NetworkCheck, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp)); Text("测试连接")
                    }
                    TextButton(onClick = { onEdit(s) }) { Icon(Icons.Outlined.Edit, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("编辑") }
                    TextButton(onClick = { confirm = s }) { Icon(Icons.Outlined.Delete, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("删除") }
                }
            }
        }
        item {
            Surface(onClick = onAdd, shape = RoundedCornerShape(Design.outer), color = Color.Transparent,
                border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(18.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Add, null, tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(8.dp))
                    Text("添加服务器", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.titleSmall)
                }
            }
        }
    }
    confirm?.let { s ->
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text("删除 ${s.name}？") },
            text = { Text("会删除这台手机上保存的地址和凭据。") },
            confirmButton = { TextButton(onClick = { confirm = null; vm.remove(s) }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { confirm = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun ModelSettings(current: LocalAgentSettings, vm: LocalAgentViewModel, onSave: (LocalAgentSettings) -> Unit) {
    val testing by vm.testing.collectAsStateWithLifecycle()
    var provider by remember(current) { mutableStateOf(current.llm.provider) }
    var baseUrl by remember(current) { mutableStateOf(current.llm.baseUrl) }
    var model by remember(current) { mutableStateOf(current.llm.model) }
    var apiKey by remember(current) { mutableStateOf(current.llm.apiKey) }
    var policy by remember(current) { mutableStateOf(current.policy) }
    val draft = LocalAgentSettings(LlmSettings(provider, baseUrl.trim(), model.trim(), apiKey.trim()), policy)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(bottom = 24.dp)) {
        SettingsGroup("模型服务", items = LlmProvider.entries.map<LlmProvider, @Composable (androidx.compose.ui.graphics.Shape) -> Unit> { p ->
            { sh ->
                PrefItem(if (p == LlmProvider.OPENAI) "OpenAI 兼容" else "Anthropic Claude", sh,
                    subtitle = if (p == LlmProvider.OPENAI) "DeepSeek、通义、Kimi、智谱、OpenRouter…" else "Claude 官方或兼容中转",
                    icon = if (p == LlmProvider.OPENAI) Icons.Outlined.Hub else Icons.Outlined.AutoAwesome,
                    tint = if (provider == p) Tint.Primary else Tint.Neutral, onClick = { provider = p },
                    modifier = Modifier.testTag("llm-${p.name.lowercase()}"),
                ) { RadioButton(provider == p, { provider = p }) }
            }
        })
        SettingsGroup("连接", items = listOf<@Composable (androidx.compose.ui.graphics.Shape) -> Unit>(
            { sh ->
                PrefItem("接口与密钥", sh, icon = Icons.Outlined.Key, below = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(baseUrl, { baseUrl = it }, label = { Text("接口地址") }, placeholder = { Text(provider.defaultBaseUrl) }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().testTag("llm-base"), shape = RoundedCornerShape(14.dp))
                        if (provider == LlmProvider.OPENAI) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            listOf("DeepSeek" to "https://api.deepseek.com/v1", "通义" to "https://dashscope.aliyuncs.com/compatible-mode/v1",
                                "Kimi" to "https://api.moonshot.cn/v1", "智谱" to "https://open.bigmodel.cn/api/paas/v4", "OpenRouter" to "https://openrouter.ai/api/v1").forEach { (n, u) ->
                                FilterChip(selected = baseUrl == u, onClick = { baseUrl = u }, label = { Text(n) })
                            }
                        }
                        OutlinedTextField(model, { model = it }, label = { Text("模型") }, placeholder = { Text(provider.defaultModel) }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().testTag("llm-model"), shape = RoundedCornerShape(14.dp))
                        OutlinedTextField(apiKey, { apiKey = it }, label = { Text("API Key") }, singleLine = true, visualTransformation = PasswordVisualTransformation(),
                            modifier = Modifier.fillMaxWidth().testTag("llm-key"), shape = RoundedCornerShape(14.dp))
                        Text("模型需要支持工具调用（function calling）。Key 只加密保存在本机，直接发给你填的接口地址。",
                            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                })
            },
        ))
        SettingsGroup("执行审批", items = ApprovalPolicy.entries.map<ApprovalPolicy, @Composable (androidx.compose.ui.graphics.Shape) -> Unit> { p ->
            { sh ->
                PrefItem(p.label, sh, subtitle = p.desc,
                    icon = when (p) { ApprovalPolicy.ALWAYS -> Icons.Outlined.PanTool; ApprovalPolicy.SAFE_AUTO -> Icons.Outlined.VerifiedUser; ApprovalPolicy.NEVER -> Icons.Outlined.GppMaybe },
                    tint = when { policy != p -> Tint.Neutral; p == ApprovalPolicy.NEVER -> Tint.Error; else -> Tint.Primary },
                    onClick = { policy = p }, modifier = Modifier.testTag("policy-${p.name.lowercase()}"),
                ) { RadioButton(policy == p, { policy = p }) }
            }
        })
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = { vm.testModel(draft.llm) }, enabled = draft.llm.configured && testing == null, modifier = Modifier.weight(1f).height(48.dp)) {
                if (testing == "llm") CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text("测试模型")
            }
            Button(onClick = { onSave(draft) }, Modifier.weight(1f).height(48.dp).testTag("llm-save")) { Text("保存") }
        }
    }
}

@Composable
private fun ServerDialog(initial: SshServer, onSave: (SshServer) -> Unit, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf(initial.name) }
    var host by remember { mutableStateOf(initial.host) }
    var port by remember { mutableStateOf(initial.port.toString()) }
    var user by remember { mutableStateOf(initial.username) }
    var useKey by remember { mutableStateOf(initial.usesKey) }
    var password by remember { mutableStateOf(initial.password) }
    var key by remember { mutableStateOf(initial.privateKey) }
    var passphrase by remember { mutableStateOf(initial.passphrase) }
    var note by remember { mutableStateOf(initial.note) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initial.name.isEmpty()) "添加服务器" else "编辑 ${initial.name}") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("名称（Agent 用它称呼）") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("srv-name"))
                OutlinedTextField(host, { host = it }, label = { Text("主机地址") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("srv-host"))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(user, { user = it }, label = { Text("用户名") }, singleLine = true, modifier = Modifier.weight(2f).testTag("srv-user"))
                    OutlinedTextField(port, { port = it.filter(Char::isDigit).take(5) }, label = { Text("端口") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.weight(1f).testTag("srv-port"))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(!useKey, { useKey = false }, { Text("密码") })
                    FilterChip(useKey, { useKey = true }, { Text("私钥") })
                }
                if (useKey) {
                    OutlinedTextField(key, { key = it }, label = { Text("私钥（PEM / OpenSSH）") }, minLines = 3, maxLines = 6, modifier = Modifier.fillMaxWidth(),
                        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
                    OutlinedTextField(passphrase, { passphrase = it }, label = { Text("私钥口令（可选）") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
                } else OutlinedTextField(password, { password = it }, label = { Text("密码") }, singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth().testTag("srv-password"))
                OutlinedTextField(note, { note = it.take(200) }, label = { Text("备注（会告诉 Agent，如：生产库，谨慎）") }, maxLines = 3, modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onSave(initial.copy(name = name, host = host, port = port.toIntOrNull() ?: 22, username = user,
                    password = if (useKey) "" else password, privateKey = if (useKey) key.trim() else "", passphrase = if (useKey) passphrase else "", note = note.trim()))
            }, Modifier.testTag("srv-save")) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

