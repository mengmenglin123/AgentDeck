package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huanmeng.huanhermes.core.hosts.HostProfile
import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.ui.vm.HostsViewModel

/** Host profiles: pick one, edit it, or add a new one (with pairing-link import). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HostsScreen(vm: HostsViewModel, onBack: () -> Unit, onConnected: () -> Unit, onScan: () -> Unit = {}) {
    val state by vm.state.collectAsStateWithLifecycle()
    var editing by remember { mutableStateOf<HostProfile?>(null) }
    var creating by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<HostProfile?>(null) }

    LaunchedEffect(state.loaded, state.profiles.isEmpty()) {
        if (state.loaded && state.profiles.isEmpty()) creating = true
    }
    val pairingStatus by vm.pairingStatus.collectAsStateWithLifecycle()
    val prefill by vm.prefill.collectAsStateWithLifecycle()
    val pendingScan by vm.pendingScan.collectAsStateWithLifecycle()
    LaunchedEffect(pendingScan) {
        val raw = pendingScan ?: return@LaunchedEffect
        vm.pendingScan.value = null
        vm.pair(raw) { ok -> if (ok) { creating = false; onConnected() } }
    }
    LaunchedEffect(prefill) { if (prefill != null) { editing = null; creating = true } }
    var nearby by rememberSaveable { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val discovery = remember { com.huanmeng.huanhermes.ui.pairing.HostDiscovery(context) }
    androidx.compose.runtime.DisposableEffect(nearby) {
        if (nearby) discovery.start()
        onDispose { discovery.stop() }
    }
    val found by discovery.found.collectAsStateWithLifecycle()
    val searching by discovery.searching.collectAsStateWithLifecycle()

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Host 连接") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
        )
        Column(
            Modifier.fillMaxSize().navigationBarsPadding().imePadding().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                androidx.compose.material3.FilledTonalButton(onClick = onScan, modifier = Modifier.weight(1f).testTag("scan-pair")) { Text("扫码配对") }
                OutlinedButton(onClick = { nearby = !nearby }, modifier = Modifier.weight(1f)) { Text(if (nearby) "停止搜索" else "附近的 Host") }
            }
            pairingStatus?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary) }
            if (nearby) {
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(if (searching) "正在局域网中搜索…" else "搜索已停止", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (found.isEmpty()) Text("还没发现 Host。确认手机和电脑在同一网络，且 Host 监听在局域网地址上。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        found.forEach { f ->
                            Row(Modifier.fillMaxWidth().clickable {
                                vm.prefill.value = f.name to HostConfig(host = f.host, bridgePort = f.bridgePort, mgmtPort = f.mgmtPort, useTls = f.tls)
                                nearby = false
                            }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.Dns, null, tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(f.name, style = MaterialTheme.typography.titleSmall)
                                    Text("${f.host} · bridge ${f.bridgePort} · mgmt ${f.mgmtPort}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Text("填入", color = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            }
            val target = editing
            if (creating || target != null) {
                HostForm(
                    initial = target,
                    prefill = if (target == null) prefill else null,
                    onPairLink = { raw -> vm.pair(raw) { ok -> if (ok) { creating = false; onConnected() } } },
                    testing = state.testing,
                    error = state.lastError,
                    onCancel = { creating = false; editing = null; vm.prefill.value = null },
                    onSubmit = { id, name, cfg ->
                        vm.testAndSave(id, name, cfg) { ok ->
                            if (ok) { creating = false; editing = null; onConnected() }
                        }
                    },
                )
            }
            state.profiles.forEach { p ->
                ElevatedCard(Modifier.fillMaxWidth().clickable { vm.select(p.id) }) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            if (p.id == state.activeId) Icons.Outlined.CheckCircle else Icons.Outlined.Dns, null,
                            tint = if (p.id == state.activeId) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(p.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                "${HostConfig.formatHost(p.config.host)} · bridge ${p.config.bridgePort} · mgmt ${p.config.mgmtPort}${if (p.config.useTls) " · TLS" else ""}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                        }
                        TextButton(onClick = { creating = false; vm.select(p.id); editing = p }) { Text("编辑") }
                        IconButton(onClick = { confirmDelete = p }) { Icon(Icons.Outlined.Delete, "删除") }
                    }
                }
            }
            if (!creating && editing == null) {
                OutlinedButton(onClick = { creating = true }, modifier = Modifier.fillMaxWidth()) { Text("添加 Host") }
            }
            state.active?.let { active ->
                if (!state.ready && !creating && editing == null) {
                    Button(
                        onClick = { vm.testAndSave(active.id, active.name, active.config) { if (it) onConnected() } },
                        enabled = !state.testing, modifier = Modifier.fillMaxWidth(),
                    ) { Text(if (state.testing) "测试中…" else "测试并连接「${active.name}」") }
                    state.lastError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }

    confirmDelete?.let { p ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("删除「${p.name}」？") },
            text = { Text("只删除本机保存的连接和令牌，不影响 Host。") },
            confirmButton = { TextButton(onClick = { vm.delete(p.id); confirmDelete = null }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { confirmDelete = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun HostForm(
    initial: HostProfile?,
    prefill: Pair<String, HostConfig>? = null,
    onPairLink: (String) -> Unit = {},
    testing: Boolean,
    error: String?,
    onCancel: () -> Unit,
    onSubmit: (String?, String, HostConfig) -> Unit,
) {
    val base = initial?.config ?: prefill?.second ?: HostConfig(bridgeToken = "", mgmtToken = "")
    val key = initial?.id ?: prefill?.second?.host
    var name by rememberSaveable(key) { mutableStateOf(initial?.name ?: prefill?.first ?: "") }
    var host by rememberSaveable(key) { mutableStateOf(base.host) }
    var bridgePort by rememberSaveable(key) { mutableStateOf(base.bridgePort.toString()) }
    var mgmtPort by rememberSaveable(key) { mutableStateOf(base.mgmtPort.toString()) }
    var bridgeToken by rememberSaveable(key) { mutableStateOf(base.bridgeToken) }
    var mgmtToken by rememberSaveable(key) { mutableStateOf(base.mgmtToken) }
    var tls by rememberSaveable(key) { mutableStateOf(base.useTls) }
    var pairing by rememberSaveable(key) { mutableStateOf("") }
    var pin by rememberSaveable(key) { mutableStateOf(base.certPin) }
    var pairingError by remember { mutableStateOf<String?>(null) }

    fun draft() = base.copy(
        host = host.trim(),
        bridgePort = bridgePort.trim().toIntOrNull() ?: -1,
        mgmtPort = mgmtPort.trim().toIntOrNull() ?: -1,
        bridgeToken = bridgeToken.trim(),
        mgmtToken = mgmtToken.trim(),
        useTls = tls,
        certPin = com.huanmeng.huanhermes.core.net.Pinning.normalize(pin),
    )

    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (initial == null) "新的 Host" else "编辑「${initial.name}」", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                pairing, { pairing = it; pairingError = null }, Modifier.fillMaxWidth(),
                label = { Text("配对链接（可选）") }, placeholder = { Text("huanhermes://connect?host=…") }, singleLine = true,
                isError = pairingError != null, supportingText = pairingError?.let { { Text(it) } },
            )
            if (pairing.isNotBlank()) {
                TextButton(onClick = {
                    val parsed = HostConfig.parsePairingUri(pairing)
                    val link = com.huanmeng.huanhermes.core.net.PairingLink.parse(pairing)
                    if (parsed == null) pairingError = "无法识别的配对链接（端口需在 1–65535）"
                    else if (link?.needsClaim == true) { onPairLink(pairing); pairing = "" }
                    else {
                        host = parsed.host; bridgePort = "${parsed.bridgePort}"; mgmtPort = "${parsed.mgmtPort}"; tls = parsed.useTls
                        if (parsed.bridgeToken.isNotEmpty()) bridgeToken = parsed.bridgeToken
                        if (parsed.mgmtToken.isNotEmpty()) mgmtToken = parsed.mgmtToken
                        if (parsed.certPin.isNotEmpty()) pin = parsed.certPin
                        pairing = ""
                    }
                }) { Text("导入配对链接") }
            }
            OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("名称") }, singleLine = true)
            OutlinedTextField(host, { host = it }, Modifier.fillMaxWidth(), label = { Text("Host（IP、域名或 IPv6）") }, singleLine = true)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    bridgePort, { bridgePort = it.filter(Char::isDigit).take(5) }, Modifier.weight(1f),
                    label = { Text("Bridge 端口") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    mgmtPort, { mgmtPort = it.filter(Char::isDigit).take(5) }, Modifier.weight(1f),
                    label = { Text("Management 端口") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
            }
            OutlinedTextField(
                bridgeToken, { bridgeToken = it }, Modifier.fillMaxWidth(), label = { Text("Bridge 令牌") },
                singleLine = true, visualTransformation = PasswordVisualTransformation(),
            )
            OutlinedTextField(
                mgmtToken, { mgmtToken = it }, Modifier.fillMaxWidth(), label = { Text("Management 令牌") },
                singleLine = true, visualTransformation = PasswordVisualTransformation(),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("使用 TLS（wss / https）", Modifier.weight(1f))
                Switch(tls, { tls = it })
            }
            if (tls) OutlinedTextField(
                pin, { pin = it.trim() }, Modifier.fillMaxWidth(), singleLine = true,
                label = { Text("证书指纹 SHA-256（可选，自签名证书必填）") },
                supportingText = { Text("openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64") },
            )
            val problems = draft().validate()
            if (problems.isNotEmpty() && (host.isNotEmpty() || bridgeToken.isNotEmpty())) {
                Text(problems.first(), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = { onSubmit(initial?.id, name, draft()) }, enabled = !testing && problems.isEmpty()) {
                    Text("测试并保存")
                }
                if (testing) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                TextButton(onClick = onCancel) { Text("取消") }
            }
        }
    }
}
