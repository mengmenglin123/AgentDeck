package com.huanmeng.huanhermes.ui.screens

import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
        Text("关于", style = MaterialTheme.typography.titleMedium)
        ElevatedCard {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("HuanHermes 原生版", style = MaterialTheme.typography.bodyLarge)
                Text(
                    "版本 ${BuildConfig.VERSION_NAME}（${BuildConfig.VERSION_CODE}）· Kotlin + Jetpack Compose",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
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
