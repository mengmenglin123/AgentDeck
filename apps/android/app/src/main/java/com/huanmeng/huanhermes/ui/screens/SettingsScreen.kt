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

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.automirrored.outlined.KeyboardReturn
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.automirrored.outlined.WrapText
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import com.huanmeng.huanhermes.ui.components.IconBadge
import com.huanmeng.huanhermes.ui.components.PrefItem
import com.huanmeng.huanhermes.ui.components.SettingsGroup
import com.huanmeng.huanhermes.ui.components.Tint
@Composable
fun SettingsScreen(settings: AppSettings, repo: SettingsRepository, onOpenHosts: () -> Unit = {}, onOpenAgent: () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current.applicationContext
    fun set(t: (AppSettings) -> AppSettings) { scope.launch { repo.update(t) } }
    var editQuick by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    val exportDoc = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) scope.launch {
            val ok = runCatching { context.contentResolver.openOutputStream(uri)?.use { it.write(repo.exportJson().toByteArray()) } }.isSuccess
            android.widget.Toast.makeText(context, if (ok) "设置已导出（不含令牌）" else "导出失败", android.widget.Toast.LENGTH_SHORT).show()
        }
    }
    val importDoc = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            val msg = runCatching {
                val raw = context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }.orEmpty()
                "已导入 ${repo.importJson(raw)} 项设置"
            }.getOrElse { "导入失败：${it.message}" }
            android.widget.Toast.makeText(context, msg, android.widget.Toast.LENGTH_SHORT).show()
        }
    }
    fun sw(title: String, sub: String?, icon: ImageVector, tint: Tint, value: Boolean, change: (Boolean) -> Unit): @Composable (Shape) -> Unit = { shape ->
        PrefItem(title, shape, subtitle = sub, icon = icon, tint = tint, onClick = { change(!value) }) { Switch(checked = value, onCheckedChange = change) }
    }

    Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Text("偏好设置", Modifier.padding(start = 28.dp, top = 20.dp, bottom = 4.dp), style = MaterialTheme.typography.headlineMedium)

        SettingsGroup("连接", items = listOf<@Composable (Shape) -> Unit>(
            { sh -> PrefItem("Host 连接", sh, subtitle = "添加、编辑、切换 Host 和令牌", icon = Icons.Outlined.Dns, onClick = onOpenHosts) },
            { sh -> PrefItem("本地 Agent", sh, subtitle = "模型、SSH 服务器与审批", icon = Icons.Outlined.SmartToy, tint = Tint.Tertiary, onClick = onOpenAgent) },
        ))

        SettingsGroup("外观", items = listOf<@Composable (Shape) -> Unit>(
            { sh ->
                PrefItem("颜色模式", sh, icon = Icons.Outlined.Contrast, below = {
                    val modes = listOf(ThemeMode.SYSTEM to "跟随系统", ThemeMode.LIGHT to "浅色", ThemeMode.DARK to "深色")
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        modes.forEachIndexed { i, (mode, label) ->
                            SegmentedButton(selected = settings.themeMode == mode, onClick = { set { it.copy(themeMode = mode) } },
                                shape = SegmentedButtonDefaults.itemShape(i, modes.size)) { Text(label) }
                        }
                    }
                })
            },
            { sh ->
                PrefItem("主题色", sh, subtitle = if (settings.dynamicColor) "已开启动态取色，主题色不生效" else null, icon = Icons.Outlined.Palette, tint = Tint.Secondary, below = {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        com.huanmeng.huanhermes.ui.theme.ThemePresets.all.forEach { p ->
                            FilterChip(selected = settings.themePreset == p.id, onClick = { set { it.copy(themePreset = p.id) } }, label = { Text(p.label) },
                                leadingIcon = { androidx.compose.foundation.layout.Box(Modifier.size(14.dp).background(p.light, CircleShape)) })
                        }
                    }
                })
            },
        ) + (if (Build.VERSION.SDK_INT >= 31) listOf<@Composable (Shape) -> Unit>(sw("动态取色（Material You）", "跟随壁纸颜色", Icons.Outlined.Wallpaper, Tint.Secondary, settings.dynamicColor) { v -> set { it.copy(dynamicColor = v) } }) else emptyList<@Composable (Shape) -> Unit>()) + listOf<@Composable (Shape) -> Unit>(
            sw("纯黑深色（OLED 省电）", null, Icons.Outlined.DarkMode, Tint.Neutral, settings.amoledBlack) { v -> set { it.copy(amoledBlack = v) } },
            sw("高对比度", null, Icons.Outlined.Visibility, Tint.Neutral, settings.highContrast) { v -> set { it.copy(highContrast = v) } },
            { sh ->
                PrefItem("字号 ${"%.0f".format(settings.fontScale * 100)}%", sh, icon = Icons.Outlined.FormatSize, tint = Tint.Secondary, below = {
                    Slider(value = settings.fontScale, onValueChange = { v -> set { it.copy(fontScale = v) } },
                        valueRange = SettingsRepository.MIN_FONT..SettingsRepository.MAX_FONT, steps = 10)
                })
            },
        ))

        SettingsGroup("对话", items = listOf<@Composable (Shape) -> Unit>(
            sw("折叠已完成轮次的工具调用", "长对话更清爽", Icons.Outlined.UnfoldLess, Tint.Primary, settings.foldTurns) { v -> set { it.copy(foldTurns = v) } },
            sw("等宽聊天字体", null, Icons.Outlined.Code, Tint.Primary, settings.monoChat) { v -> set { it.copy(monoChat = v) } },
            sw("回车发送", "Shift+回车换行", Icons.AutoMirrored.Outlined.KeyboardReturn, Tint.Primary, settings.enterToSend) { v -> set { it.copy(enterToSend = v) } },
            sw("代码块显示行号", null, Icons.Outlined.FormatListNumbered, Tint.Primary, settings.codeLineNumbers) { v -> set { it.copy(codeLineNumbers = v) } },
            sw("代码块自动换行", null, Icons.AutoMirrored.Outlined.WrapText, Tint.Primary, settings.codeWrap) { v -> set { it.copy(codeWrap = v) } },
            { sh -> PrefItem("快捷消息", sh, subtitle = "${settings.quickMessages.size} 条，输入框为空时显示", icon = Icons.Outlined.Bolt, onClick = { editQuick = true }) },
            sw("触感反馈", null, Icons.Outlined.Vibration, Tint.Neutral, settings.haptics) { v -> set { it.copy(haptics = v) } },
            sw("保持屏幕常亮", null, Icons.Outlined.LightMode, Tint.Neutral, settings.keepScreenOn) { v -> set { it.copy(keepScreenOn = v) } },
        ))

        SettingsGroup("会话列表与工具", items = listOf<@Composable (Shape) -> Unit>(
            sw("紧凑会话列表", null, Icons.Outlined.ViewAgenda, Tint.Secondary, settings.compactList) { v -> set { it.copy(compactList = v) } },
            { sh ->
                PrefItem("会话排序", sh, icon = Icons.AutoMirrored.Outlined.Sort, tint = Tint.Secondary, below = {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        com.huanmeng.huanhermes.core.overview.SessionSort.entries.forEach { sort ->
                            FilterChip(selected = settings.sessionSort == sort, onClick = { set { it.copy(sessionSort = sort) } }, label = { Text(sort.label) })
                        }
                    }
                })
            },
            sw("仪表盘每 30 秒自动刷新", null, Icons.Outlined.Autorenew, Tint.Secondary, settings.dashboardAutoRefresh) { v -> set { it.copy(dashboardAutoRefresh = v) } },
            { sh ->
                PrefItem("终端字号 ${settings.terminalFontSp.toInt()} sp", sh, icon = Icons.Outlined.Terminal, tint = Tint.Secondary, below = {
                    Slider(value = settings.terminalFontSp, onValueChange = { v -> set { it.copy(terminalFontSp = v) } }, valueRange = 10f..20f, steps = 9)
                })
            },
        ))

        SettingsGroup("安全", items = listOf<@Composable (Shape) -> Unit>(
            sw("App 锁", "离开 1 分钟后需解锁", Icons.Outlined.Lock, Tint.Tertiary, settings.appLock) { v -> set { it.copy(appLock = v) } },
            sw("「本会话允许」前验证", "指纹或锁屏密码", Icons.Outlined.Fingerprint, Tint.Tertiary, settings.confirmAllowAll) { v -> set { it.copy(confirmAllowAll = v) } },
        ))

        SettingsGroup("通知与推送", items = listOf<@Composable (Shape) -> Unit>(
            sw("后台审批通知", "可在通知里直接允许 / 拒绝", Icons.Outlined.NotificationsActive, Tint.Primary, settings.approvalNotifications) { v ->
                set { it.copy(approvalNotifications = v) }
                com.huanmeng.huanhermes.notify.InboxWorker.schedule(context, v)
            },
            { sh ->
                PrefItem("UnifiedPush 实时推送", sh, icon = Icons.Outlined.CellTower, below = {
                    PushRow(settings.pushEndpoint, onDisable = {
                        runCatching { org.unifiedpush.android.connector.UnifiedPush.unregister(context) }
                        set { it.copy(pushEndpoint = null) }
                    })
                })
            },
            sw("保持连接", "前台服务每 30 秒检查，较耗电", Icons.Outlined.Sync, Tint.Neutral, settings.keepAlive) { v ->
                set { it.copy(keepAlive = v) }
                com.huanmeng.huanhermes.notify.KeepAliveService.set(context, v)
            },
        ))

        SettingsGroup("数据", items = listOf<@Composable (Shape) -> Unit>(
            { sh -> PrefItem("导出设置", sh, subtitle = "JSON 文件，不含令牌", icon = Icons.Outlined.Upload, tint = Tint.Secondary, onClick = { exportDoc.launch("huanhermes-settings.json") }) },
            { sh -> PrefItem("导入设置", sh, icon = Icons.Outlined.Download, tint = Tint.Secondary, onClick = { importDoc.launch(arrayOf("application/json", "text/*")) }) },
            { sh ->
                PrefItem("复制本机偏好", sh, subtitle = "排查问题时发给开发者", icon = Icons.Outlined.ContentCopy, tint = Tint.Secondary, onClick = {
                    val summary = "HuanHermes ${BuildConfig.VERSION_NAME} 本机偏好（不含令牌）\n" + listOf(
                        "主题" to settings.themeMode.name, "字号" to "${(settings.fontScale * 100).toInt()}%", "高对比" to settings.highContrast,
                        "纯黑" to settings.amoledBlack, "动态取色" to settings.dynamicColor, "折叠工具调用" to settings.foldTurns,
                        "触感" to settings.haptics, "审批通知" to settings.approvalNotifications, "UnifiedPush" to (settings.pushEndpoint != null),
                        "保持连接" to settings.keepAlive, "屏幕常亮" to settings.keepScreenOn, "终端字号" to settings.terminalFontSp.toInt(),
                        "仪表盘自动刷新" to settings.dashboardAutoRefresh, "紧凑列表" to settings.compactList, "排序" to settings.sessionSort.label,
                        "等宽聊天" to settings.monoChat,
                    ).joinToString("\n") { (k, v) -> "$k：$v" }
                    com.huanmeng.huanhermes.ui.chat.copyToClipboard(context, summary, "HuanHermes 偏好")
                })
            },
            { sh -> PrefItem("恢复默认偏好", sh, subtitle = "Host、令牌和推送保持不变", icon = Icons.Outlined.RestartAlt, tint = Tint.Error, onClick = { confirmReset = true }) },
        ))

        SettingsGroup("关于", items = listOf<@Composable (Shape) -> Unit>(
            { sh ->
                PrefItem("HuanHermes 原生版", sh, subtitle = "版本 ${BuildConfig.VERSION_NAME}（${BuildConfig.VERSION_CODE}）· Kotlin + Jetpack Compose", icon = Icons.Outlined.Info, tint = Tint.Neutral, below = {
                    Text("令牌只保存在本机加密存储（Android Keystore），不备份、不上传。推送只带会话引用，内容由 App 通过你自己的 Host 读取。不含统计或广告 SDK。",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                })
            },
        ))
        Spacer(Modifier.height(16.dp))
    }

    if (editQuick) {
        var text by remember { mutableStateOf(settings.quickMessages.joinToString("\n")) }
        AlertDialog(
            onDismissRequest = { editQuick = false },
            title = { Text("快捷消息") },
            text = {
                Column {
                    Text("每行一条，最多 8 条；输入框为空时显示", style = MaterialTheme.typography.bodySmall)
                    OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth().padding(top = 8.dp), minLines = 4)
                }
            },
            confirmButton = { TextButton(onClick = { set { it.copy(quickMessages = text.lines().map(String::trim).filter(String::isNotEmpty).take(8)) }; editQuick = false }) { Text("保存") } },
            dismissButton = { TextButton(onClick = { editQuick = false }) { Text("取消") } },
        )
    }
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        title = { Text("恢复默认偏好？") },
        text = { Text("外观、对话和终端设置会恢复默认；Host 连接、令牌和推送注册保持不变。") },
        confirmButton = {
            TextButton(onClick = {
                confirmReset = false
                set { AppSettings(askedNotificationPermission = it.askedNotificationPermission, pushEndpoint = it.pushEndpoint, keepAlive = it.keepAlive, approvalNotifications = it.approvalNotifications) }
            }) { Text("恢复") }
        },
        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text("取消") } },
    )
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
