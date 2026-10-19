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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocalAgentScreen(vm: LocalAgentViewModel, onBack: () -> Unit) {
    val ctl = vm.ctl
    val settings by ctl.settings.collectAsStateWithLifecycle()
    val servers by ctl.servers.servers.collectAsStateWithLifecycle()
    val toast by vm.toast.collectAsStateWithLifecycle()
    val prompt by vm.prompt.collectAsStateWithLifecycle()
    val ctx = androidx.compose.ui.platform.LocalContext.current
    var tab by rememberSaveable { mutableStateOf(if (settings.llm.configured) 0 else 2) }
    var editing by remember { mutableStateOf<SshServer?>(null) }
    var confirmClear by remember { mutableStateOf(false) }
    LaunchedEffect(toast) { toast?.let { android.widget.Toast.makeText(ctx, it, android.widget.Toast.LENGTH_SHORT).show(); vm.toast.value = null } }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("本地 Agent") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = { if (tab == 0) IconButton(onClick = { confirmClear = true }, Modifier.testTag("agent-clear")) { Icon(Icons.Outlined.RestartAlt, "新对话") } },
            )
        },
        floatingActionButton = {
            if (tab == 1) ExtendedFloatingActionButton(
                onClick = { editing = SshServer(name = "", host = "", username = "") },
                icon = { Icon(Icons.Outlined.Add, null) }, text = { Text("添加服务器") },
                modifier = Modifier.testTag("agent-add-server"),
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            TabRow(selectedTabIndex = tab) {
                listOf("对话", "服务器 ${servers.size}", "模型").forEachIndexed { i, t ->
                    Tab(selected = tab == i, onClick = { tab = i }, text = { Text(t) }, modifier = Modifier.testTag("agent-tab-$i"))
                }
            }
            when (tab) {
                0 -> AgentChat(ctl, settings, servers.isEmpty(), onSetup = { tab = it })
                1 -> ServerList(servers, vm, onEdit = { editing = it })
                else -> ModelSettings(settings, vm, onSave = { ctl.saveSettings(it); vm.toast.value = "已保存" })
            }
        }
    }
    editing?.let { s -> ServerDialog(s, onSave = { vm.save(it) { editing = null } }, onDismiss = { editing = null }) }
    prompt?.let { p ->
        AlertDialog(
            onDismissRequest = {},
            title = { Text(if (p.previous == null) "确认主机指纹" else "主机指纹已变化！") },
            text = {
                Column {
                    Text(if (p.previous == null) "第一次连接 ${p.host}，请核对服务器的 ${p.algorithm} 指纹：" else "${p.host} 的指纹和上次不同，可能被劫持。上次：${p.previous}")
                    Spacer(Modifier.size(8.dp))
                    Text(p.fingerprint, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
                }
            },
            confirmButton = { TextButton(onClick = { vm.answer(true) }, Modifier.testTag("agent-trust")) { Text("信任") } },
            dismissButton = { TextButton(onClick = { vm.answer(false) }) { Text("取消") } },
        )
    }
    if (confirmClear) AlertDialog(
        onDismissRequest = { confirmClear = false },
        title = { Text("开始新对话？") },
        text = { Text("当前对话记录会清空，正在进行的任务会停止。") },
        confirmButton = { TextButton(onClick = { confirmClear = false; ctl.clear() }) { Text("清空") } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("取消") } },
    )
}

private sealed class AgentRow(val key: String) {
    class User(key: String, val text: String) : AgentRow(key)
    class Reply(key: String, val text: String) : AgentRow(key)
    class Tool(key: String, val callId: String) : AgentRow(key)
}

@Composable
private fun AgentChat(ctl: LocalAgentController, settings: LocalAgentSettings, noServers: Boolean, onSetup: (Int) -> Unit) {
    val messages by ctl.agent.messages.collectAsStateWithLifecycle()
    val activities by ctl.agent.activities.collectAsStateWithLifecycle()
    val running by ctl.agent.running.collectAsStateWithLifecycle()
    val error by ctl.agent.error.collectAsStateWithLifecycle()
    val approval by ctl.agent.approval.collectAsStateWithLifecycle()
    var input by rememberSaveable { mutableStateOf("") }
    val list = rememberLazyListState()
    val rows = remember(messages) {
        messages.flatMapIndexed { i, m ->
            when (m) {
                is AgentMessage.User -> listOf<AgentRow>(AgentRow.User("u$i", m.text))
                is AgentMessage.Assistant -> buildList { if (m.text.isNotBlank()) add(AgentRow.Reply("a$i", m.text)); m.toolCalls.forEach { add(AgentRow.Tool("t$i-${it.id}", it.id)) } }
                is AgentMessage.ToolResult -> emptyList()
            }
        }
    }
    LaunchedEffect(rows.size, activities.size, running) { if (rows.isNotEmpty()) list.animateScrollToItem(rows.size) }
    Column(Modifier.fillMaxSize().imePadding()) {
        Box(Modifier.weight(1f)) {
            LazyColumn(Modifier.fillMaxSize().testTag("agent-list"), state = list, contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (rows.isEmpty()) item {
                    Column(Modifier.fillMaxWidth().padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("用自然语言管理你的服务器", style = MaterialTheme.typography.titleMedium)
                        Text("Agent 在手机上运行，用你自己的模型 API Key，通过 SSH 在已保存的服务器上执行命令、读写文件。", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (!settings.llm.configured) OutlinedButton(onClick = { onSetup(2) }) { Text("先配置模型") }
                        if (noServers) OutlinedButton(onClick = { onSetup(1) }) { Text("添加 SSH 服务器") }
                        listOf("看看所有服务器的磁盘和内存", "nginx 为什么起不来？", "把 web 上的系统更新一下").forEach { s ->
                            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.clickable { input = s }) {
                                Text(s, Modifier.padding(horizontal = 12.dp, vertical = 8.dp), style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
                items(rows, key = { it.key }) { r ->
                    when (r) {
                        is AgentRow.User -> Row(Modifier.fillMaxWidth()) {
                            Spacer(Modifier.weight(1f).width(48.dp))
                            Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                                SelectionContainer { Text(r.text, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onPrimaryContainer) }
                            }
                        }
                        is AgentRow.Tool -> activities[r.callId]?.let { a ->
                            ToolCard(a, waiting = approval?.activity?.callId == a.callId, onAnswer = ctl.agent::answerApproval)
                        }
                        is AgentRow.Reply -> SelectionContainer { MarkdownView(r.text, Modifier.fillMaxWidth().testTag("agent-reply"), MaterialTheme.typography.bodyMedium) }
                    }
                }
                if (running && approval == null) item { Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("思考中…", style = MaterialTheme.typography.bodySmall) } }
                error?.let { e -> item { Text(e, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("agent-error")) } }
            }
        }
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                input, { input = it }, Modifier.weight(1f).heightIn(max = 160.dp).testTag("agent-input"),
                placeholder = { Text(if (settings.llm.configured) "让 Agent 帮你做点什么…" else "请先在「模型」页配置 API Key") },
                enabled = settings.llm.configured,
            )
            Spacer(Modifier.width(4.dp))
            if (running) IconButton(onClick = ctl::stop, Modifier.testTag("agent-stop")) { Icon(Icons.Outlined.Stop, "停止") }
            else IconButton(onClick = { ctl.send(input); input = "" }, enabled = input.isNotBlank() && settings.llm.configured, modifier = Modifier.testTag("agent-send")) {
                Icon(Icons.AutoMirrored.Filled.Send, "发送")
            }
        }
        Text("审批：${settings.policy.label}", Modifier.padding(start = 16.dp, bottom = 6.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ToolCard(a: ToolActivity, waiting: Boolean, onAnswer: (Boolean) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val (icon, tint) = when (a.state) {
        ToolActivity.State.WAITING_APPROVAL -> Icons.Outlined.HourglassTop to MaterialTheme.colorScheme.tertiary
        ToolActivity.State.RUNNING -> Icons.Outlined.Terminal to MaterialTheme.colorScheme.primary
        ToolActivity.State.DONE -> Icons.Outlined.CheckCircle to MaterialTheme.colorScheme.primary
        ToolActivity.State.FAILED -> Icons.Outlined.ErrorOutline to MaterialTheme.colorScheme.error
        ToolActivity.State.DENIED -> Icons.Outlined.Block to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Card(
        Modifier.fillMaxWidth().animateContentSize().clickable(enabled = a.output.isNotEmpty()) { open = !open }.testTag("agent-tool-${a.state.name.lowercase()}"),
        colors = CardDefaults.cardColors(containerColor = if (waiting) MaterialTheme.colorScheme.tertiaryContainer else MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (a.state == ToolActivity.State.RUNNING) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Icon(icon, null, Modifier.size(18.dp), tint = tint)
                Spacer(Modifier.width(8.dp))
                Text(a.server ?: "本机", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text(when (a.state) { ToolActivity.State.WAITING_APPROVAL -> "等待批准"; ToolActivity.State.RUNNING -> "执行中"; ToolActivity.State.DONE -> "完成"; ToolActivity.State.FAILED -> "失败"; ToolActivity.State.DENIED -> "已拒绝" },
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(a.summary, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall, maxLines = if (open || waiting) 20 else 3, overflow = TextOverflow.Ellipsis)
            if (waiting) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { onAnswer(true) }, Modifier.testTag("agent-approve")) { Text("批准执行") }
                OutlinedButton(onClick = { onAnswer(false) }, Modifier.testTag("agent-deny")) { Text("拒绝") }
            }
            if (open && a.output.isNotEmpty()) Surface(shape = RoundedCornerShape(8.dp), color = MaterialTheme.colorScheme.surface) {
                SelectionContainer { Text(a.output.take(20_000), Modifier.padding(8.dp).fillMaxWidth(), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
            } else if (a.output.isNotEmpty()) Text("点开看输出", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ServerList(servers: List<SshServer>, vm: LocalAgentViewModel, onEdit: (SshServer) -> Unit) {
    val testing by vm.testing.collectAsStateWithLifecycle()
    var confirm by remember { mutableStateOf<SshServer?>(null) }
    LazyColumn(Modifier.fillMaxSize().testTag("agent-servers"), contentPadding = PaddingValues(12.dp, 12.dp, 12.dp, 88.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (servers.isEmpty()) item {
            Text("还没有服务器。添加后，本地 Agent 就能通过 SSH 操作它们。密码和私钥只加密保存在这台手机上。", Modifier.padding(8.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        items(servers, key = { it.id }) { s ->
            ElevatedCard(Modifier.fillMaxWidth().testTag("agent-server-${s.name}")) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(s.name, style = MaterialTheme.typography.titleMedium)
                    Text(s.label() + " · " + (if (s.usesKey) "私钥" else "密码"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (s.note.isNotBlank()) Text(s.note, style = MaterialTheme.typography.bodySmall)
                    Text(if (s.hostKey.isBlank()) "未确认主机指纹，Agent 使用前请先测试连接" else "指纹 ${s.hostKey.take(22)}…",
                        style = MaterialTheme.typography.labelSmall, color = if (s.hostKey.isBlank()) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        FilledTonalButton(onClick = { vm.test(s) }, enabled = testing == null, modifier = Modifier.testTag("agent-test-${s.name}")) {
                            if (testing == s.id) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp) else Text("测试连接")
                        }
                        Spacer(Modifier.weight(1f))
                        IconButton(onClick = { onEdit(s) }) { Icon(Icons.Outlined.Edit, "编辑") }
                        IconButton(onClick = { confirm = s }) { Icon(Icons.Outlined.Delete, "删除") }
                    }
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

@Composable
private fun ModelSettings(current: LocalAgentSettings, vm: LocalAgentViewModel, onSave: (LocalAgentSettings) -> Unit) {
    val testing by vm.testing.collectAsStateWithLifecycle()
    var provider by remember(current) { mutableStateOf(current.llm.provider) }
    var baseUrl by remember(current) { mutableStateOf(current.llm.baseUrl) }
    var model by remember(current) { mutableStateOf(current.llm.model) }
    var apiKey by remember(current) { mutableStateOf(current.llm.apiKey) }
    var policy by remember(current) { mutableStateOf(current.policy) }
    val draft = LocalAgentSettings(LlmSettings(provider, baseUrl.trim(), model.trim(), apiKey.trim()), policy)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("模型服务", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        LlmProvider.entries.forEach { p ->
            Row(Modifier.fillMaxWidth().clickable { provider = p }, verticalAlignment = Alignment.CenterVertically) {
                RadioButton(provider == p, { provider = p }, Modifier.testTag("llm-${p.name.lowercase()}")); Text(p.label, style = MaterialTheme.typography.bodyMedium)
            }
        }
        OutlinedTextField(baseUrl, { baseUrl = it }, label = { Text("接口地址") }, placeholder = { Text(provider.defaultBaseUrl) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("llm-base"))
        Text(if (provider == LlmProvider.OPENAI) "例：https://api.deepseek.com/v1、https://dashscope.aliyuncs.com/compatible-mode/v1、https://openrouter.ai/api/v1" else "留空使用官方地址",
            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedTextField(model, { model = it }, label = { Text("模型") }, placeholder = { Text(provider.defaultModel) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("llm-model"))
        OutlinedTextField(apiKey, { apiKey = it }, label = { Text("API Key") }, singleLine = true, visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth().testTag("llm-key"))
        Text("模型需要支持工具调用（function calling）。API Key 只加密保存在本机，直接发给你填的接口地址。", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("执行审批", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        ApprovalPolicy.entries.forEach { p ->
            Row(Modifier.fillMaxWidth().clickable { policy = p }, verticalAlignment = Alignment.CenterVertically) {
                RadioButton(policy == p, { policy = p }, Modifier.testTag("policy-${p.name.lowercase()}"))
                Column { Text(p.label, style = MaterialTheme.typography.bodyMedium); Text(p.desc, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { onSave(draft) }, Modifier.testTag("llm-save")) { Text("保存") }
            OutlinedButton(onClick = { vm.testModel(draft.llm) }, enabled = draft.llm.configured && testing == null) {
                if (testing == "llm") CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp) else Text("测试模型")
            }
        }
    }
}
