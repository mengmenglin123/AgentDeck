package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import com.huanmeng.huanhermes.ui.components.PrefItem
import com.huanmeng.huanhermes.ui.components.Tint
import com.huanmeng.huanhermes.ui.components.groupShape
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
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

private data class Tool(val name: String, val desc: String, val icon: ImageVector, val milestone: String? = null, val action: String? = null)
private data class Section(val title: String, val tools: List<Tool>)

private val sections = listOf(
    Section("常用", listOf(
        Tool("需要我", "所有 Host 上等待你批准的操作", Icons.Outlined.PanTool, action = "inbox"),
        Tool("Host 连接", "添加、切换 Host 与令牌", Icons.Outlined.Dns, action = "hosts"),
        Tool("本地 Agent", "用自己的模型 Key，通过 SSH 操作服务器", Icons.Outlined.SmartToy, action = "agent"),
    )),
    Section("Host 状态", listOf(
        Tool("Status", "版本、运行时间、能力", Icons.Outlined.MonitorHeart, action = "status"),
        Tool("Dashboard", "会话与运行概览", Icons.Outlined.Dashboard, action = "dashboard"),
        Tool("Activity", "最近事件流", Icons.Outlined.Insights, action = "catalog/ACTIVITY"),
        Tool("Logs", "Host 日志", Icons.AutoMirrored.Outlined.ReceiptLong, action = "catalog/LOGS"),
        Tool("Audit", "权限审批记录", Icons.Outlined.Security, action = "catalog/AUDIT"),
    )),
    Section("Agent 能力", listOf(
        Tool("Agents", "可用的 Agent 与驱动", Icons.Outlined.SmartToy, action = "catalog/AGENTS"),
        Tool("Skills", "技能目录", Icons.Outlined.Psychology, action = "catalog/SKILLS"),
        Tool("MCP", "MCP 服务器与工具", Icons.Outlined.Extension, action = "catalog/MCP"),
        Tool("Tools", "内置工具清单", Icons.Outlined.Handyman, action = "catalog/TOOLS"),
        Tool("Memory", "长期记忆", Icons.Outlined.AccountTree, action = "catalog/MEMORY"),
        Tool("扩展", "MCP 服务、技能、连接器", Icons.Outlined.Extension, action = "extensions"),
        Tool("Cron", "定时任务", Icons.Outlined.Schedule, action = "catalog/CRON"),
        Tool("定时提示", "按计划自动发给会话", Icons.Outlined.Alarm, action = "automations"),
    )),
    Section("代码与终端", listOf(
        Tool("Workspace", "浏览项目文件", Icons.Outlined.Folder, action = "workspace"),
        Tool("Diff", "Git 状态与改动", Icons.Outlined.Difference, action = "git"),
        Tool("终端", "远程终端（PTY）", Icons.Outlined.Terminal, action = "terminal"),
        Tool("CLI 会话", "电脑上已有的 Claude Code 会话", Icons.Outlined.History, action = "external"),
    )),
    Section("配对与安装", listOf(
        Tool("扫码配对", "扫描 Host 二维码一键连接", Icons.Outlined.QrCodeScanner, action = "scan"),
        Tool("SSH 安装", "一键安装 companion", Icons.Outlined.InstallDesktop, action = "ssh"),
    )),
)

@Composable
fun ToolsScreen(onOpenHosts: () -> Unit = {}, onOpenInbox: () -> Unit = {}, onOpen: (String) -> Unit = {}) {
    val tints = listOf(Tint.Primary, Tint.Secondary, Tint.Tertiary, Tint.Primary, Tint.Secondary)
    LazyColumn(Modifier.fillMaxSize().statusBarsPadding().testTag("tools-list"), contentPadding = PaddingValues(bottom = 24.dp)) {
        item(key = "title") { Text("工具箱", Modifier.padding(start = 28.dp, top = 20.dp, bottom = 4.dp), style = MaterialTheme.typography.headlineMedium) }
        sections.forEachIndexed { si, section ->
            item(key = "h-${section.title}") {
                Text(
                    section.title,
                    Modifier.padding(start = 28.dp, end = 16.dp, top = 18.dp, bottom = 8.dp),
                    style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
                )
            }
            itemsIndexed(section.tools, key = { _, t -> t.name }) { i, tool ->
                val tag = "tool-" + tool.name.lowercase()
                PrefItem(
                    tool.name, groupShape(i, section.tools.size),
                    Modifier.padding(horizontal = 16.dp, vertical = 1.dp).testTag(tag),
                    subtitle = tool.desc, icon = tool.icon, tint = tints[si % tints.size], enabled = tool.action != null,
                    onClick = { when (tool.action) { "hosts" -> onOpenHosts(); "inbox" -> onOpenInbox(); null -> {}; else -> onOpen(tool.action) } },
                    trailing = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
                )
            }
        }
    }
}
