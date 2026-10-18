package com.huanmeng.huanhermes.ui.screens

import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.TextButton
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.BuildConfig
import com.huanmeng.huanhermes.data.AppSettings
import com.huanmeng.huanhermes.data.SettingsRepository
import com.huanmeng.huanhermes.data.ThemeMode
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(settings: AppSettings, repo: SettingsRepository, onOpenHosts: () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current.applicationContext
    fun set(t: (AppSettings) -> AppSettings) { scope.launch { repo.update(t) } }

    Column(
        Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("连接", style = MaterialTheme.typography.titleMedium)
        ElevatedCard(Modifier.fillMaxWidth().clickable(onClick = onOpenHosts)) {
            Column(Modifier.padding(16.dp)) {
                Text("Host 连接", style = MaterialTheme.typography.bodyLarge)
                Text("添加、编辑、切换 Host 和令牌", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text("外观", style = MaterialTheme.typography.titleMedium)
        ElevatedCard {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                val modes = listOf(ThemeMode.SYSTEM to "跟随系统", ThemeMode.LIGHT to "浅色", ThemeMode.DARK to "深色")
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    modes.forEachIndexed { i, (mode, label) ->
                        SegmentedButton(
                            selected = settings.themeMode == mode,
                            onClick = { set { it.copy(themeMode = mode) } },
                            shape = SegmentedButtonDefaults.itemShape(i, modes.size),
                        ) { Text(label) }
                    }
                }
                if (Build.VERSION.SDK_INT >= 31) {
                    SwitchRow("动态取色（Material You）", settings.dynamicColor) { v -> set { it.copy(dynamicColor = v) } }
                }
                SwitchRow("纯黑深色（OLED 省电）", settings.amoledBlack) { v -> set { it.copy(amoledBlack = v) } }
                SwitchRow("高对比度", settings.highContrast) { v -> set { it.copy(highContrast = v) } }
                Text("字号 ${"%.0f".format(settings.fontScale * 100)}%", style = MaterialTheme.typography.bodyMedium)
                Slider(
                    value = settings.fontScale,
                    onValueChange = { v -> set { it.copy(fontScale = v) } },
                    valueRange = SettingsRepository.MIN_FONT..SettingsRepository.MAX_FONT,
                    steps = 10,
                )
            }
        }
        Text("对话", style = MaterialTheme.typography.titleMedium)
        ElevatedCard {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SwitchRow("折叠已完成轮次的工具调用", settings.foldTurns) { v -> set { it.copy(foldTurns = v) } }
                SwitchRow("触感反馈", settings.haptics) { v -> set { it.copy(haptics = v) } }
                SwitchRow("保持屏幕常亮", settings.keepScreenOn) { v -> set { it.copy(keepScreenOn = v) } }
                Text("主题色", style = MaterialTheme.typography.bodyMedium)
                androidx.compose.foundation.layout.Row(
                    Modifier.horizontalScroll(androidx.compose.foundation.rememberScrollState()),
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                ) {
                    com.huanmeng.huanhermes.ui.theme.ThemePresets.all.forEach { p ->
                        androidx.compose.material3.FilterChip(
                            selected = settings.themePreset == p.id,
                            onClick = { set { it.copy(themePreset = p.id) } },
                            label = { Text(p.label) },
                            leadingIcon = {
                                androidx.compose.foundation.layout.Box(
                                    Modifier.size(14.dp).background(p.light, androidx.compose.foundation.shape.CircleShape),
                                )
                            },
                        )
                    }
                }
                if (settings.dynamicColor) Text("已开启动态取色，主题色不生效", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                SwitchRow("等宽聊天字体", settings.monoChat) { v -> set { it.copy(monoChat = v) } }
                SwitchRow("回车发送（Shift+回车换行）", settings.enterToSend) { v -> set { it.copy(enterToSend = v) } }
                SwitchRow("「本会话允许」前验证指纹/锁屏密码", settings.confirmAllowAll) { v -> set { it.copy(confirmAllowAll = v) } }
                SwitchRow("App 锁（离开 1 分钟后需解锁）", settings.appLock) { v -> set { it.copy(appLock = v) } }
                SwitchRow("代码块显示行号", settings.codeLineNumbers) { v -> set { it.copy(codeLineNumbers = v) } }
                SwitchRow("代码块自动换行", settings.codeWrap) { v -> set { it.copy(codeWrap = v) } }
                var editQuick by remember { mutableStateOf(false) }
                androidx.compose.material3.OutlinedButton(onClick = { editQuick = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("编辑快捷消息（${settings.quickMessages.size}）")
                }
                if (editQuick) {
                    var text by remember { mutableStateOf(settings.quickMessages.joinToString("\n")) }
                    androidx.compose.material3.AlertDialog(
                        onDismissRequest = { editQuick = false },
                        title = { Text("快捷消息") },
                        text = {
                            Column {
                                Text("每行一条，最多 8 条；输入框为空时显示", style = MaterialTheme.typography.bodySmall)
                                androidx.compose.material3.OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth().padding(top = 8.dp), minLines = 4)
                            }
                        },
                        confirmButton = { TextButton(onClick = { set { it.copy(quickMessages = text.lines().map(String::trim).filter(String::isNotEmpty).take(8)) }; editQuick = false }) { Text("保存") } },
                        dismissButton = { TextButton(onClick = { editQuick = false }) { Text("取消") } },
                    )
                }
                SwitchRow("紧凑会话列表", settings.compactList) { v -> set { it.copy(compactList = v) } }
                Text("会话排序", style = MaterialTheme.typography.bodyMedium)
                androidx.compose.foundation.layout.Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                    com.huanmeng.huanhermes.core.overview.SessionSort.entries.forEach { sort ->
                        androidx.compose.material3.FilterChip(
                            selected = settings.sessionSort == sort,
                            onClick = { set { it.copy(sessionSort = sort) } },
                            label = { Text(sort.label) },
                        )
                    }
                }
                SwitchRow("仪表盘每 30 秒自动刷新", settings.dashboardAutoRefresh) { v -> set { it.copy(dashboardAutoRefresh = v) } }
                Text("终端字号 ${settings.terminalFontSp.toInt()} sp", style = MaterialTheme.typography.bodyMedium)
                Slider(
                    value = settings.terminalFontSp,
                    onValueChange = { v -> set { it.copy(terminalFontSp = v) } },
                    valueRange = 10f..20f, steps = 9,
                )
                SwitchRow("后台审批通知（可在通知里直接允许/拒绝）", settings.approvalNotifications) { v ->
                    set { it.copy(approvalNotifications = v) }
                    com.huanmeng.huanhermes.notify.InboxWorker.schedule(context, v)
                }
            }
        }
        Text("推送", style = MaterialTheme.typography.titleMedium)
        ElevatedCard {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                PushRow(settings.pushEndpoint, onDisable = {
                    runCatching { org.unifiedpush.android.connector.UnifiedPush.unregister(context) }
                    set { it.copy(pushEndpoint = null) }
                })
                SwitchRow("保持连接（前台服务，每 30 秒检查，较耗电）", settings.keepAlive) { v ->
                    set { it.copy(keepAlive = v) }
                    com.huanmeng.huanhermes.notify.KeepAliveService.set(context, v)
                }
                Text(
                    "没有推送分发器时，后台大约每 15 分钟检查一次；离开 App 后的前几分钟检查更频繁。",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        var confirmReset by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
        androidx.compose.material3.OutlinedButton(onClick = {
            val summary = "HuanHermes ${BuildConfig.VERSION_NAME} 本机偏好（不含令牌）\n" + listOf(
                "主题" to settings.themeMode.name, "字号" to "${(settings.fontScale * 100).toInt()}%", "高对比" to settings.highContrast,
                "纯黑" to settings.amoledBlack, "动态取色" to settings.dynamicColor, "折叠工具调用" to settings.foldTurns,
                "触感" to settings.haptics, "审批通知" to settings.approvalNotifications, "UnifiedPush" to (settings.pushEndpoint != null),
                "保持连接" to settings.keepAlive, "屏幕常亮" to settings.keepScreenOn, "终端字号" to settings.terminalFontSp.toInt(),
                "仪表盘自动刷新" to settings.dashboardAutoRefresh, "紧凑列表" to settings.compactList, "排序" to settings.sessionSort.label,
                "等宽聊天" to settings.monoChat,
            ).joinToString("\n") { (k, v) -> "$k：$v" }
            com.huanmeng.huanhermes.ui.chat.copyToClipboard(context, summary, "HuanHermes 偏好")
        }, modifier = Modifier.fillMaxWidth()) { Text("复制本机偏好") }
        androidx.compose.material3.OutlinedButton(onClick = { confirmReset = true }, modifier = Modifier.fillMaxWidth()) { Text("恢复默认偏好") }
        if (confirmReset) androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("恢复默认偏好？") },
            text = { Text("外观、对话和终端设置会恢复默认；Host 连接、令牌和推送注册保持不变。") },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmReset = false
                    set { AppSettings(askedNotificationPermission = it.askedNotificationPermission, pushEndpoint = it.pushEndpoint, keepAlive = it.keepAlive, approvalNotifications = it.approvalNotifications) }
                }) { Text("恢复") }
            },
            dismissButton = { androidx.compose.material3.TextButton(onClick = { confirmReset = false }) { Text("取消") } },
        )
        Text("关于", style = MaterialTheme.typography.titleMedium)
        ElevatedCard {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("HuanHermes 原生版", style = MaterialTheme.typography.bodyLarge)
                Text(
                    "版本 ${BuildConfig.VERSION_NAME}（${BuildConfig.VERSION_CODE}）· Kotlin + Jetpack Compose",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "隐私：令牌只保存在本机加密存储（Android Keystore），不备份、不上传。推送消息只带会话引用，内容由 App 通过你自己的 Host 读取。App 不含统计或广告 SDK。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun PushRow(endpoint: String?, onDisable: () -> Unit) {
    val activity = androidx.compose.ui.platform.LocalContext.current.let { c ->
        var x = c
        while (x is android.content.ContextWrapper && x !is android.app.Activity) x = x.baseContext
        x as? android.app.Activity
    }
    var message by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf<String?>(null) }
    androidx.compose.foundation.layout.Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("UnifiedPush 实时推送", style = MaterialTheme.typography.bodyLarge)
            val host = endpoint?.let { runCatching { android.net.Uri.parse(it).host }.getOrNull() }
            Text(
                message ?: if (endpoint != null) "已启用 · ${host ?: "分发器"}" else "通过 ntfy 等分发器即时唤醒，无需 Google 服务",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (endpoint != null) {
            androidx.compose.material3.TextButton(onClick = onDisable) { Text("停用") }
        } else {
            androidx.compose.material3.FilledTonalButton(onClick = {
                val a = activity ?: return@FilledTonalButton
                runCatching {
                    org.unifiedpush.android.connector.UnifiedPush.tryUseCurrentOrDefaultDistributor(a) { ok ->
                        if (ok) {
                            org.unifiedpush.android.connector.UnifiedPush.register(a, messageForDistributor = "HuanHermes 审批通知")
                            message = "正在向分发器注册…"
                        } else {
                            message = "没有找到分发器：先安装 ntfy（F-Droid / Play）再试"
                        }
                    }
                }.onFailure { message = "启用失败：${it.message}" }
            }) { Text("启用") }
        }
    }
}
