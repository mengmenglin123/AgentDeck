package com.huanmeng.huanhermes.ui.chat

import com.huanmeng.huanhermes.ui.components.AppCard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.core.chat.ChatItem
import com.huanmeng.huanhermes.ui.theme.Brand

private fun decidedLabel(d: String) = when (d) {
    "accept" -> "已接受计划"
    "accept_clear" -> "已接受并清空上下文"
    "keep" -> "已要求继续规划"
    "submit" -> "已回答"
    "deny" -> "已跳过"
    else -> "已处理"
}

/** Plan approval: 接受 / 接受并清空上下文 / 继续规划（附反馈）. */
@Composable
fun PlanCard(item: ChatItem.Permission, onAnswer: (String, String?, Map<String, List<String>>?) -> Unit) {
    var feedback by rememberSaveable(item.id) { mutableStateOf("") }
    var keeping by rememberSaveable(item.id) { mutableStateOf(false) }
    val has = { s: String -> item.buttons.any { it.data.endsWith(":$s") } }
    AppCard(Modifier.fillMaxWidth().testTag("plan-card")) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(if (item.decision == null) Icons.Outlined.Map else Icons.Outlined.CheckCircle, null, Modifier.size(18.dp),
                    tint = if (item.decision == null) Brand.warning else Brand.success)
                Spacer(Modifier.width(6.dp))
                Text(item.decision?.let { "计划 · ${decidedLabel(it)}" } ?: "计划 · 等你确认", style = MaterialTheme.typography.titleSmall)
            }
            MarkdownView(item.text, style = MaterialTheme.typography.bodyMedium)
            if (item.decision == null) {
                if (keeping) {
                    OutlinedTextField(feedback, { feedback = it }, Modifier.fillMaxWidth().testTag("plan-feedback"), placeholder = { Text("哪里要改？（可留空）") }, minLines = 2)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onAnswer("keep", feedback.ifBlank { null }, null) }) { Text("发送并继续规划") }
                        TextButton(onClick = { keeping = false }) { Text("取消") }
                    }
                } else Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (has("accept")) Button(onClick = { onAnswer("accept", null, null) }, Modifier.fillMaxWidth()) { Text("接受并开始执行") }
                    if (has("accept_clear")) OutlinedButton(onClick = { onAnswer("accept_clear", null, null) }, Modifier.fillMaxWidth()) { Text("接受并清空上下文") }
                    if (has("keep")) OutlinedButton(onClick = { keeping = true }, Modifier.fillMaxWidth()) { Text("继续规划…") }
                    if (has("deny")) TextButton(onClick = { onAnswer("deny", null, null) }) { Text("拒绝") }
                }
            }
        }
    }
}

/** AskUserQuestion as a native form: single / multi choice per question, plus "other". */
@Composable
fun QuestionCard(item: ChatItem.Permission, onAnswer: (String, String?, Map<String, List<String>>?) -> Unit) {
    var picked by androidx.compose.runtime.remember(item.id) { mutableStateOf(mapOf<String, List<String>>()) }
    var other by rememberSaveable(item.id) { mutableStateOf("") }
    AppCard(Modifier.fillMaxWidth().testTag("question-card")) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(if (item.decision == null) Icons.AutoMirrored.Outlined.HelpOutline else Icons.Outlined.CheckCircle, null, Modifier.size(18.dp),
                    tint = if (item.decision == null) Brand.warning else Brand.success)
                Spacer(Modifier.width(6.dp))
                Text(item.decision?.let { "Agent 的问题 · ${decidedLabel(it)}" } ?: "Agent 的问题", style = MaterialTheme.typography.titleSmall)
            }
            if (item.text.isNotBlank() && item.questions.isEmpty()) MarkdownView(item.text, style = MaterialTheme.typography.bodyMedium)
            item.questions.forEach { q ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(listOfNotNull(q.header, q.question).joinToString(" · "), style = MaterialTheme.typography.bodyMedium)
                    if (q.multiSelect) Text("可多选", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    q.options.forEach { o ->
                        val chosen = picked[q.id].orEmpty().contains(o.label)
                        val toggle = {
                            if (item.decision == null) {
                                val cur = picked[q.id].orEmpty()
                                val next = if (q.multiSelect) (if (chosen) cur - o.label else cur + o.label) else listOf(o.label)
                                picked = picked + (q.id to next)
                            }
                        }
                        Row(
                            Modifier.fillMaxWidth().clickable(role = if (q.multiSelect) Role.Checkbox else Role.RadioButton, onClick = toggle),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            if (q.multiSelect) Checkbox(chosen, { toggle() }, enabled = item.decision == null)
                            else RadioButton(chosen, { toggle() }, enabled = item.decision == null)
                            Column {
                                Text(o.label, style = MaterialTheme.typography.bodyMedium)
                                o.description?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            }
                        }
                    }
                }
            }
            if (item.decision == null) {
                OutlinedTextField(other, { other = it }, Modifier.fillMaxWidth(), placeholder = { Text("补充说明（可选）") })
                val complete = item.questions.all { picked[it.id].orEmpty().isNotEmpty() } || other.isNotBlank()
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { onAnswer("submit", other.ifBlank { null }, picked.filterValues { it.isNotEmpty() }) }, enabled = complete) { Text("提交回答") }
                    if (item.buttons.any { it.data.endsWith(":deny") }) TextButton(onClick = { onAnswer("deny", null, null) }) { Text("跳过") }
                }
            }
        }
    }
}
