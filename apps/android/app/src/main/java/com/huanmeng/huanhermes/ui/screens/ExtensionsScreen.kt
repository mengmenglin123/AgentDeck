package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.extensions.Connector
import com.huanmeng.huanhermes.core.extensions.Extensions
import com.huanmeng.huanhermes.core.extensions.McpServer
import com.huanmeng.huanhermes.core.extensions.McpSpec
import com.huanmeng.huanhermes.core.extensions.SkillInfo
import com.huanmeng.huanhermes.ui.vm.ExtensionsViewModel

/** 扩展：MCP 服务、技能、连接器（预设的 MCP）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExtensionsScreen(vm: ExtensionsViewModel, onBack: () -> Unit, initialTab: Int = 0) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(initialTab) }
    var addMcp by remember { mutableStateOf(false) }
    var addSkill by remember { mutableStateOf(false) }
    var connect by remember { mutableStateOf<Connector?>(null) }
    var confirmRemove by remember { mutableStateOf<String?>(null) }
    var confirmDeleteSkill by remember { mutableStateOf<String?>(null) }
    val ctx = LocalContext.current
    LaunchedEffect(ui.result) {
        ui.result?.let { android.widget.Toast.makeText(ctx, it, android.widget.Toast.LENGTH_SHORT).show(); vm.clearResult() }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("扩展") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = { IconButton(onClick = { vm.refresh() }) { Icon(Icons.Outlined.Refresh, "刷新") } },
            )
        },
        floatingActionButton = {
            if (ui.canWrite && tab != 2) ExtendedFloatingActionButton(
                onClick = { if (tab == 0) addMcp = true else addSkill = true },
                icon = { Icon(Icons.Outlined.Add, null) },
                text = { Text(if (tab == 0) "添加 MCP" else "新建技能") },
                modifier = Modifier.testTag("ext-fab"),
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            TabRow(selectedTabIndex = tab) {
                listOf("MCP 服务", "技能", "连接器").forEachIndexed { i, t ->
                    Tab(selected = tab == i, onClick = { tab = i }, text = { Text(t) }, modifier = Modifier.testTag("ext-tab-$i"))
                }
            }
            ProjectChips(ui.projects, ui.project, vm::selectProject)
            if (ui.loading || ui.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (!ui.loading && !ui.canWrite) ReadOnlyHint(ui.discovers)
            ui.error?.let { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) }
            when (tab) {
                0 -> McpList(ui.servers, ui.canWrite, onProbe = vm::probe, onRemove = { confirmRemove = it })
                1 -> SkillList(ui.skills, onOpen = vm::openSkill, onDelete = { confirmDeleteSkill = it })
                else -> ConnectorList(ui.servers.map { it.name }.toSet(), ui.canWrite, onConnect = { connect = it })
            }
        }
    }
    if (addMcp) AddMcpDialog(onSave = { addMcp = false; vm.addServer(it) }, onDismiss = { addMcp = false })
    if (addSkill) AddSkillDialog(onSave = { n, d, b -> addSkill = false; vm.createSkill(n, d, b) }, onDismiss = { addSkill = false })
    connect?.let { c -> ConnectDialog(c, onSave = { spec -> connect = null; vm.addServer(spec) }, onDismiss = { connect = null }) }
    confirmRemove?.let { name ->
        AlertDialog(
            onDismissRequest = { confirmRemove = null },
            title = { Text("移除 $name？") },
            text = { Text("会从项目的 MCP 配置文件里删掉这一项，新会话里不再加载。") },
            confirmButton = { TextButton(onClick = { confirmRemove = null; vm.removeServer(name) }) { Text("移除") } },
            dismissButton = { TextButton(onClick = { confirmRemove = null }) { Text("取消") } },
        )
    }
    confirmDeleteSkill?.let { id ->
        AlertDialog(
            onDismissRequest = { confirmDeleteSkill = null },
            title = { Text("删除技能 $id？") },
            text = { Text("会删除项目里这个技能的整个目录。") },
            confirmButton = { TextButton(onClick = { confirmDeleteSkill = null; vm.deleteSkill(id) }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { confirmDeleteSkill = null }) { Text("取消") } },
        )
    }
    ui.probe?.let { (name, tools) ->
        AlertDialog(
            onDismissRequest = vm::dismiss,
            title = { Text("$name · ${tools.size} 个工具") },
            text = {
                Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()).testTag("probe-tools")) {
                    if (tools.isEmpty()) Text("这个服务没有公开任何工具。")
                    tools.forEach { t ->
                        Text(t.name, style = MaterialTheme.typography.titleSmall, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(top = 8.dp))
                        if (t.description.isNotBlank()) Text(t.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            },
            confirmButton = { TextButton(onClick = vm::dismiss) { Text("好") } },
        )
    }
    ui.skillView?.let { (id, content, path) ->
        AlertDialog(
            onDismissRequest = vm::dismiss,
            title = { Text(id) },
            text = {
                Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState()).testTag("skill-content")) {
                    path?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text(content, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(top = 8.dp))
                }
            },
            confirmButton = { TextButton(onClick = vm::dismiss) { Text("关闭") } },
        )
    }
}

@Composable
private fun ReadOnlyHint(discovers: Boolean) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), shape = MaterialTheme.shapes.medium) {
        Text(
            (if (discovers) "这个 Host 只读。" else "这个 Host 只提供配置里写好的名单。") +
                "要在手机上添加、删除或查看工具，请在 Host 配置的 [workspace] 里加 extensions_write = true 并重启。",
            Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun McpList(servers: List<McpServer>, canWrite: Boolean, onProbe: (String) -> Unit, onRemove: (String) -> Unit) {
    LazyColumn(Modifier.fillMaxSize().testTag("mcp-list"), contentPadding = PaddingValues(12.dp, 8.dp, 12.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (servers.isEmpty()) item { Text("这个项目还没有 MCP 服务。去「连接器」里一键接入常用服务，或点右下角手动添加。", Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(servers, key = { it.name }) { s ->
            ElevatedCard(Modifier.fillMaxWidth().testTag("mcp-${s.name}")) {
                Column(Modifier.padding(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(s.name, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        if (!s.enabled) Text("已停用", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
                    }
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOfNotNull(s.kind, scopeLabel(s.scope), if (s.tools.isNotEmpty()) "${s.tools.size} 个工具" else null,
                            if (s.secretKeys.isNotEmpty()) "含密钥 ${s.secretKeys.joinToString(",")}" else null)
                            .forEach { AssistChip(onClick = {}, label = { Text(it, style = MaterialTheme.typography.labelSmall) }) }
                    }
                    if (s.target.isNotBlank()) Text(s.target, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (canWrite) Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { onProbe(s.name) }, modifier = Modifier.testTag("probe-${s.name}")) { Text("查看工具") }
                        if (s.editable) TextButton(onClick = { onRemove(s.name) }) { Text("移除") }
                    }
                }
            }
        }
    }
}

private fun scopeLabel(scope: String) = when (scope) {
    "project" -> "项目"; "user" -> "用户全局"; "local" -> "本机项目"; "host" -> "Host 配置"; else -> scope
}

@Composable
private fun SkillList(skills: List<SkillInfo>, onOpen: (String) -> Unit, onDelete: (String) -> Unit) {
    LazyColumn(Modifier.fillMaxSize().testTag("skill-list"), contentPadding = PaddingValues(12.dp, 8.dp, 12.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (skills.isEmpty()) item { Text("还没有技能。技能是一份 SKILL.md 说明书，Agent 遇到相关任务时会自动读它。", Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(skills, key = { it.scope + it.id }) { s ->
            ElevatedCard(Modifier.fillMaxWidth().clickable { onOpen(s.id) }.testTag("skill-${s.id}")) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(s.name, style = MaterialTheme.typography.titleMedium)
                        if (s.description.isNotBlank()) Text(s.description, style = MaterialTheme.typography.bodySmall, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        Text(scopeLabel(s.scope) + (s.path?.let { " · $it" } ?: ""), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (s.editable) TextButton(onClick = { onDelete(s.id) }) { Text("删除") }
                }
            }
        }
    }
}

@Composable
private fun ConnectorList(installed: Set<String>, canWrite: Boolean, onConnect: (Connector) -> Unit) {
    val uri = LocalUriHandler.current
    LazyColumn(Modifier.fillMaxSize().testTag("connector-list"), contentPadding = PaddingValues(12.dp, 8.dp, 12.dp, 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items(Extensions.connectors, key = { it.id }) { c ->
            val done = c.id in installed
            ElevatedCard(Modifier.fillMaxWidth().testTag("connector-${c.id}")) {
                Column(Modifier.padding(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(c.title, style = MaterialTheme.typography.titleMedium)
                            Text("${c.category} · ${c.summary}", style = MaterialTheme.typography.bodySmall)
                        }
                        when {
                            done -> Text("已接入", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge)
                            canWrite -> OutlinedButton(onClick = { onConnect(c) }) { Text("接入") }
                        }
                    }
                    c.needs?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    TextButton(onClick = { runCatching { uri.openUri(c.docs) } }, contentPadding = PaddingValues(0.dp)) { Text("说明") }
                }
            }
        }
    }
}

private const val SECRET_NOTE = "密钥会以明文写进 Host 上的配置文件（项目的 .mcp.json，Codex 是 ~/.codex/config.toml），只在你自己的机器上。"

@Composable
private fun ConnectDialog(c: Connector, onSave: (McpSpec) -> Unit, onDismiss: () -> Unit) {
    val values = remember { mutableStateOf(c.fields.associate { it.key to "" }) }
    val missing = c.fields.any { values.value[it.key].isNullOrBlank() }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("接入 ${c.title}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(c.summary, style = MaterialTheme.typography.bodySmall)
                c.needs?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                c.fields.forEach { f ->
                    OutlinedTextField(
                        values.value[f.key].orEmpty(), { v -> values.value = values.value + (f.key to v) },
                        Modifier.fillMaxWidth().testTag("connector-field-${f.key}"),
                        label = { Text(f.label) }, placeholder = { Text(f.placeholder) }, singleLine = true,
                        supportingText = if (f.hint.isNotBlank()) ({ Text(f.hint) }) else null,
                        visualTransformation = if (f.secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
                        keyboardOptions = if (f.secret) KeyboardOptions(keyboardType = KeyboardType.Password) else KeyboardOptions.Default,
                    )
                }
                if (c.fields.any { it.secret }) Text(SECRET_NOTE, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = { TextButton(onClick = { onSave(c.build(values.value.mapValues { it.value.trim() })) }, enabled = !missing) { Text("接入") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

@Composable
private fun AddMcpDialog(onSave: (McpSpec) -> Unit, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var http by remember { mutableStateOf(false) }
    var command by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var pairs by remember { mutableStateOf("") }
    val spec = run {
        val (cmd, args) = Extensions.splitCommand(command)
        if (http) McpSpec(name.trim(), "http", url = url.trim(), headers = Extensions.parsePairs(pairs))
        else McpSpec(name.trim(), "stdio", cmd, args, env = Extensions.parsePairs(pairs))
    }
    val problem = spec.problem()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("添加 MCP 服务") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth().testTag("mcp-name"), label = { Text("名称") }, singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = !http, onClick = { http = false }, label = { Text("本机命令 stdio") })
                    FilterChip(selected = http, onClick = { http = true }, label = { Text("远程 HTTP") })
                }
                if (http) OutlinedTextField(url, { url = it }, Modifier.fillMaxWidth().testTag("mcp-url"), label = { Text("地址") }, placeholder = { Text("https://…/mcp") }, singleLine = true)
                else OutlinedTextField(command, { command = it }, Modifier.fillMaxWidth().testTag("mcp-command"), label = { Text("启动命令") }, placeholder = { Text("npx -y @scope/server") }, singleLine = true)
                OutlinedTextField(pairs, { pairs = it }, Modifier.fillMaxWidth(), label = { Text(if (http) "请求头（每行 KEY=VALUE，可空）" else "环境变量（每行 KEY=VALUE，可空）") }, minLines = 2)
                Text(SECRET_NOTE, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (name.isNotBlank() && problem != null) Text(problem, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall)
            }
        },
        confirmButton = { TextButton(onClick = { onSave(spec) }, enabled = problem == null) { Text("添加") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

@Composable
private fun AddSkillDialog(onSave: (String, String, String) -> Unit, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var desc by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    val nameProblem = Extensions.skillNameProblem(name)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("新建技能") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it.lowercase() }, Modifier.fillMaxWidth().testTag("skill-name"), label = { Text("名称") }, placeholder = { Text("deploy-check") }, singleLine = true,
                    isError = name.isNotEmpty() && nameProblem != null, supportingText = if (name.isNotEmpty() && nameProblem != null) ({ Text(nameProblem) }) else null)
                OutlinedTextField(desc, { desc = it }, Modifier.fillMaxWidth().testTag("skill-desc"), label = { Text("什么时候用（描述）") }, placeholder = { Text("发布前检查版本号、changelog 和签名") }, minLines = 2)
                OutlinedTextField(body, { body = it }, Modifier.fillMaxWidth().testTag("skill-body"), label = { Text("步骤 / 说明（Markdown）") }, minLines = 4)
                Text("保存到项目的技能目录（Claude Code：.claude/skills，Codex：.agents/skills），新会话里生效。", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = { TextButton(onClick = { onSave(name, desc, body) }, enabled = nameProblem == null && desc.isNotBlank()) { Text("保存") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}
