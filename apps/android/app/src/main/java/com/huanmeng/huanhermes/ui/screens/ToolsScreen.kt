package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.automirrored.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Difference
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Handyman
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.InstallDesktop
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.SmartToy
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

private data class Tool(val name: String, val desc: String, val icon: ImageVector, val milestone: String? = null, val action: String? = null)
private data class Section(val title: String, val tools: List<Tool>)

private val sections = listOf(
    Section("常用", listOf(
        Tool("需要我", "所有 Host 上等待你批准的操作", Icons.Outlined.PanTool, action = "inbox"),
        Tool("Host 连接", "添加、切换 Host 与令牌", Icons.Outlined.Dns, action = "hosts"),
    )),
    Section("Host 状态", listOf(
        Tool("Status", "版本、运行时间、能力", Icons.Outlined.MonitorHeart, "0.2.4"),
        Tool("Dashboard", "会话与运行概览", Icons.Outlined.Dashboard, "0.2.4"),
        Tool("Activity", "最近事件流", Icons.Outlined.Insights, "0.2.4"),
        Tool("Logs", "Host 日志", Icons.AutoMirrored.Outlined.ReceiptLong, "0.2.4"),
        Tool("Audit", "权限审批记录", Icons.Outlined.Security, "0.2.4"),
    )),
    Section("Agent 能力", listOf(
        Tool("Agents", "可用的 Agent 与驱动", Icons.Outlined.SmartToy, "0.2.4"),
        Tool("Skills", "技能目录", Icons.Outlined.Psychology, "0.2.4"),
        Tool("MCP", "MCP 服务器与工具", Icons.Outlined.Extension, "0.2.4"),
        Tool("Tools", "内置工具清单", Icons.Outlined.Handyman, "0.2.4"),
        Tool("Memory", "长期记忆", Icons.Outlined.AccountTree, "0.2.4"),
        Tool("Cron", "定时任务", Icons.Outlined.Schedule, "0.2.4"),
    )),
    Section("代码与终端", listOf(
        Tool("Workspace", "浏览项目文件", Icons.Outlined.Folder, "0.2.5"),
        Tool("Diff", "查看改动", Icons.Outlined.Difference, "0.2.5"),
        Tool("终端", "远程终端（PTY）", Icons.Outlined.Terminal, "0.2.5"),
    )),
    Section("配对与安装", listOf(
        Tool("扫码配对", "扫描 Host 二维码一键连接", Icons.Outlined.QrCodeScanner, "0.2.6"),
        Tool("SSH 安装", "一键安装 companion", Icons.Outlined.InstallDesktop, "0.2.6"),
    )),
)

@Composable
fun ToolsScreen(onOpenHosts: () -> Unit = {}, onOpenInbox: () -> Unit = {}) {
    LazyColumn(Modifier.fillMaxSize().statusBarsPadding(), contentPadding = PaddingValues(vertical = 8.dp)) {
        sections.forEach { section ->
            item(key = "h-${section.title}") {
                Text(
                    section.title,
                    Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
                    style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
                )
            }
            items(section.tools, key = { it.name }) { tool ->
                val enabled = tool.action != null
                ListItem(
                    modifier = Modifier.fillMaxWidth().clickable(enabled = enabled) {
                        when (tool.action) { "hosts" -> onOpenHosts(); "inbox" -> onOpenInbox() }
                    },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                    leadingContent = { Icon(tool.icon, null, tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) },
                    headlineContent = { Text(tool.name) },
                    supportingContent = { Text(tool.desc, style = MaterialTheme.typography.bodySmall) },
                    trailingContent = {
                        tool.milestone?.let { Text("${it} 上线", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    },
                )
            }
        }
    }
}
