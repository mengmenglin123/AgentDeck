package com.huanmeng.huanhermes.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Calculate
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.core.agent.AgentAttachment
import com.huanmeng.huanhermes.core.agent.SkillPack
import com.huanmeng.huanhermes.core.agent.SkillPacks
import com.huanmeng.huanhermes.ui.components.IconBadge
import com.huanmeng.huanhermes.ui.components.Tint
import com.huanmeng.huanhermes.ui.components.groupShape

fun skillIcon(name: String?): ImageVector = when (name) {
    "dns" -> Icons.Outlined.Dns
    "travel_explore" -> Icons.Outlined.TravelExplore
    "description" -> Icons.Outlined.Description
    "code" -> Icons.Outlined.Code
    "calculate" -> Icons.Outlined.Calculate
    "translate" -> Icons.Outlined.Translate
    "edit_note" -> Icons.Outlined.EditNote
    else -> Icons.Outlined.AutoAwesome
}

private val skillTints = listOf(Tint.Primary, Tint.Secondary, Tint.Tertiary)
fun skillTint(p: SkillPack?): Tint = if (p == null) Tint.Neutral else skillTints[SkillPacks.all.indexOf(p).coerceAtLeast(0) % skillTints.size]

/** Icon for a phone-side tool card (null = not a phone tool). */
fun phoneToolIcon(tool: String): ImageVector? = when (tool) {
    "web_search" -> Icons.Outlined.Search
    "web_fetch" -> Icons.Outlined.Public
    "run_javascript" -> Icons.Outlined.Code
    "current_time" -> Icons.Outlined.Schedule
    else -> null
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SkillPickerSheet(current: String?, onPick: (String?) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Text("技能", Modifier.padding(start = 24.dp, bottom = 4.dp), style = MaterialTheme.typography.titleLarge)
        Text("选一个技能，Agent 会按这个角色工作", Modifier.padding(start = 24.dp, bottom = 8.dp),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        val entries = listOf<SkillPack?>(null) + SkillPacks.all
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 560.dp).testTag("skill-picker"), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
            itemsIndexed(entries, key = { _, p -> p?.id ?: "none" }) { i, p ->
                val sel = p?.id == current
                Surface(onClick = { onPick(p?.id) }, shape = groupShape(i, entries.size, 22.dp, 6.dp),
                    color = if (sel) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 1.dp).testTag("skill-${p?.id ?: "none"}")) {
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconBadge(skillIcon(p?.icon), if (sel) Tint.Primary else skillTint(p), 38.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(p?.name ?: "通用", style = MaterialTheme.typography.titleSmall)
                            Text(p?.description ?: "不限定角色，按需使用全部工具", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                        if (sel) Icon(Icons.Outlined.CheckCircle, "当前", tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

/** A file chip; [onRemove] null = read-only (inside a sent message). */
@Composable
fun AttachmentChip(a: AgentAttachment, onRemove: (() -> Unit)? = null) {
    val image = a.imageBase64 != null
    Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest) {
        Row(Modifier.padding(start = 8.dp, end = if (onRemove != null) 0.dp else 10.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconBadge(if (image) Icons.Outlined.Image else Icons.Outlined.Description, if (image) Tint.Tertiary else Tint.Secondary, 26.dp)
            Spacer(Modifier.width(6.dp))
            Column(Modifier.widthIn(max = 160.dp)) {
                Text(a.name, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(if (image) "图片" else "${a.text?.length ?: 0} 字", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (onRemove != null) IconButton(onClick = onRemove, Modifier.size(32.dp)) { Icon(Icons.Outlined.Close, "移除 ${a.name}", Modifier.size(16.dp)) }
        }
    }
}

@Composable
fun AttachmentRow(list: List<AgentAttachment>, onRemove: ((Int) -> Unit)? = null, modifier: Modifier = Modifier) {
    if (list.isEmpty()) return
    LazyRow(modifier.testTag("agent-attachments"), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        items(list.size) { i -> AttachmentChip(list[i], onRemove?.let { f -> { f(i) } }) }
    }
}
