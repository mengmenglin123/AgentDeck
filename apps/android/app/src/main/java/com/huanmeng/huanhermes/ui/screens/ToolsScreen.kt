package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

private data class Tool(val name: String, val milestone: String)

private val tools = listOf(
    Tool("待我处理", "0.2.2"), Tool("Status", "0.2.3"), Tool("Dashboard", "0.2.3"),
    Tool("Agents", "0.2.3"), Tool("Skills", "0.2.3"), Tool("MCP", "0.2.3"),
    Tool("Cron", "0.2.3"), Tool("Memory", "0.2.3"), Tool("Activity", "0.2.3"),
    Tool("Logs", "0.2.3"), Tool("Tools", "0.2.3"), Tool("Audit", "0.2.3"),
    Tool("Workspace", "0.2.4"), Tool("Diff", "0.2.4"), Tool("终端", "0.2.4"),
    Tool("扫码配对", "0.2.5"), Tool("SSH 安装", "0.2.5"),
)

@Composable
fun ToolsScreen() {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(150.dp),
        modifier = Modifier.fillMaxSize().statusBarsPadding(),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(tools) { tool ->
            ElevatedCard {
                Column(Modifier.padding(16.dp)) {
                    Text(tool.name, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "${tool.milestone} 上线",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
