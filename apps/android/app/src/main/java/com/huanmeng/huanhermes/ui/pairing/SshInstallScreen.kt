package com.huanmeng.huanhermes.ui.pairing

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.huanmeng.huanhermes.core.ssh.CompanionBundle
import com.huanmeng.huanhermes.core.ssh.CompanionInstaller
import com.huanmeng.huanhermes.core.ssh.SshTarget
import com.huanmeng.huanhermes.core.ssh.TrileadSshRunner
import com.huanmeng.huanhermes.data.AppGraph
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Host key prompt: first sight (TOFU) or a changed key. */
data class HostKeyPrompt(val host: String, val algorithm: String, val fingerprint: String, val previous: String?, val answer: CompletableDeferred<Boolean>)

class SshInstallViewModel(private val graph: AppGraph, private val context: Context) : ViewModel() {
    val progress = MutableStateFlow<String?>(null)
    val error = MutableStateFlow<String?>(null)
    val prompt = MutableStateFlow<HostKeyPrompt?>(null)
    val running = MutableStateFlow(false)
    private val known = context.getSharedPreferences("ssh_known_hosts", Context.MODE_PRIVATE)

    private fun bundle(): CompanionBundle {
        val meta = Json.parseToJsonElement(context.assets.open("companion/companion.json").bufferedReader().readText()).jsonObject
        val file = meta["file"]!!.jsonPrimitive.content
        return CompanionBundle(meta["version"]!!.jsonPrimitive.content, meta["sha256"]!!.jsonPrimitive.content, context.assets.open("companion/$file").readBytes())
    }

    /** Runs on sshlib's thread: blocks until the user answers the dialog. */
    private fun verify(host: String, port: Int, algorithm: String, fingerprint: String): Boolean {
        val key = "$host:$port"
        val previous = known.getString(key, null)
        if (previous == fingerprint) return true
        val answer = CompletableDeferred<Boolean>()
        prompt.value = HostKeyPrompt(host, algorithm, fingerprint, previous, answer)
        val ok = runBlocking { answer.await() }
        prompt.value = null
        if (ok) known.edit().putString(key, fingerprint).apply()
        return ok
    }

    fun install(target: SshTarget, name: String, lan: Boolean, onDone: () -> Unit) = viewModelScope.launch {
        running.value = true; error.value = null
        try {
            val result = CompanionInstaller.install(
                target, bundle(),
                connect = { t -> TrileadSshRunner(t, { alg, fp -> verify(t.host.trim(), t.port, alg, fp) }) },
                progress = { progress.value = it },
                lan = lan,
            )
            progress.value = if (result.serviceStarted) "已安装 ${result.version} 并启动，正在连接…" else "已安装 ${result.version}，正在连接…"
            // The service needs a moment to bind its ports.
            var ok = false
            repeat(5) { attempt ->
                if (!ok) {
                    if (attempt > 0) kotlinx.coroutines.delay(2_000)
                    ok = graph.profiles.testAndSave(null, name.ifBlank { target.host.trim() }, result.config)
                }
            }
            if (ok) { progress.value = null; onDone() }
            else error.value = (graph.profiles.state.value.lastError ?: "连接失败") +
                if (!result.serviceStarted) "。Host 服务未自动启动，请在服务器上运行 systemctl --user start huanhermes-host" else ""
        } catch (e: Exception) {
            error.value = e.message ?: e.javaClass.simpleName
        } finally {
            running.value = false
        }
    }

    fun answer(ok: Boolean) { prompt.value?.answer?.complete(ok) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SshInstallScreen(vm: SshInstallViewModel, onBack: () -> Unit, onConnected: () -> Unit) {
    val progress by vm.progress.collectAsStateWithLifecycle()
    val error by vm.error.collectAsStateWithLifecycle()
    val prompt by vm.prompt.collectAsStateWithLifecycle()
    val running by vm.running.collectAsStateWithLifecycle()
    var host by rememberSaveable { mutableStateOf("") }
    var port by rememberSaveable { mutableStateOf("22") }
    var user by rememberSaveable { mutableStateOf("") }
    var useKey by rememberSaveable { mutableStateOf(false) }
    var password by rememberSaveable { mutableStateOf("") }
    var key by rememberSaveable { mutableStateOf("") }
    var passphrase by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    var lan by rememberSaveable { mutableStateOf(true) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SSH 一键安装") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
            )
        },
    ) { pad ->
        Column(
            Modifier.padding(pad).fillMaxSize().imePadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                "通过 SSH 把内置的 Host companion 上传到你的电脑或服务器，校验 SHA-256 后安装、生成令牌并启动服务。密码和私钥只用于这次连接，不会保存。",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(host, { host = it.trim() }, Modifier.fillMaxWidth(), label = { Text("服务器地址") }, singleLine = true)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(user, { user = it.trim() }, Modifier.weight(2f), label = { Text("用户名") }, singleLine = true)
                OutlinedTextField(port, { port = it.filter(Char::isDigit).take(5) }, Modifier.weight(1f), label = { Text("端口") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = !useKey, onClick = { useKey = false }, label = { Text("密码") })
                FilterChip(selected = useKey, onClick = { useKey = true }, label = { Text("私钥") })
            }
            if (!useKey) {
                OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(), label = { Text("SSH 密码") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation())
            } else {
                OutlinedTextField(key, { key = it }, Modifier.fillMaxWidth(), label = { Text("私钥（PEM / OpenSSH）") }, minLines = 3, maxLines = 6,
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
                OutlinedTextField(passphrase, { passphrase = it }, Modifier.fillMaxWidth(), label = { Text("私钥口令（可选）") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation())
            }
            OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("在 App 里显示的名称（可选）") }, singleLine = true)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(lan, { lan = it })
                Column {
                    Text("允许手机直接连接（监听局域网）")
                    Text("关闭后 Host 只监听 127.0.0.1，需要 Tailscale / 反向代理等方式访问", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            progress?.let { p ->
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (running) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text(p, Modifier.padding(start = 12.dp))
                    }
                }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            val ready = host.isNotBlank() && user.isNotBlank() && (port.toIntOrNull() ?: 0) in 1..65535 &&
                (if (useKey) key.isNotBlank() else password.isNotEmpty())
            Button(
                onClick = {
                    vm.install(
                        SshTarget(host, port.toInt(), user, password.takeIf { !useKey }, key.takeIf { useKey }, passphrase.takeIf { useKey && it.isNotEmpty() }),
                        name, lan, onConnected,
                    )
                },
                enabled = ready && !running, modifier = Modifier.fillMaxWidth(),
            ) { Text(if (running) "安装中…" else "安装并连接") }
        }
    }
    prompt?.let { p ->
        AlertDialog(
            onDismissRequest = {},
            title = { Text(if (p.previous == null) "确认服务器指纹" else "⚠ 服务器指纹已变化") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(if (p.previous == null) "第一次连接 ${p.host}，请和服务器上 ssh-keygen -lf 的结果核对：" else "${p.host} 的主机密钥和上次不同，可能是重装了系统，也可能有人在中间拦截。")
                    Text("${p.algorithm}\n${p.fingerprint}", fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
                    p.previous?.let { Text("上次：$it", fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            },
            confirmButton = { TextButton(onClick = { vm.answer(true) }) { Text("信任并继续") } },
            dismissButton = { TextButton(onClick = { vm.answer(false) }) { Text("取消") } },
        )
    }
}
