package com.huanmeng.huanhermes.ui.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.huanmeng.huanhermes.core.protocol.Attachment
import java.io.ByteArrayOutputStream

/** Reading attachments from content URIs; images are downscaled so they fit the 5 MB limit. */
object AttachmentReader {
    private const val MAX_SIDE = 2048

    fun read(context: Context, uri: Uri): Attachment? = runCatching {
        val cr = context.contentResolver
        val mime = cr.getType(uri) ?: "application/octet-stream"
        var name = "attachment"
        cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.let { name = it }
        }
        val bytes = cr.openInputStream(uri)?.use { input ->
            val buf = ByteArrayOutputStream()
            val chunk = ByteArray(64 * 1024)
            var total = 0
            while (true) {
                val n = input.read(chunk)
                if (n < 0) break
                total += n
                if (total > 24 * 1024 * 1024) return@runCatching null // far too big even for an image
                buf.write(chunk, 0, n)
            }
            buf.toByteArray()
        } ?: return@runCatching null
        if (mime.startsWith("image/") && mime != "image/gif" && bytes.size > 1024 * 1024) shrink(name, bytes) ?: Attachment(name, mime, bytes)
        else Attachment(name, mime, bytes)
    }.getOrNull()

    fun fromBitmap(name: String, bitmap: Bitmap): Attachment = Attachment(name, "image/jpeg", jpeg(scaled(bitmap)))

    private fun shrink(name: String, bytes: ByteArray): Attachment? {
        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val base = name.substringBeforeLast('.', name)
        return Attachment("$base.jpg", "image/jpeg", jpeg(scaled(bmp)))
    }

    private fun scaled(b: Bitmap): Bitmap {
        val side = maxOf(b.width, b.height)
        if (side <= MAX_SIDE) return b
        val f = MAX_SIDE.toFloat() / side
        return Bitmap.createScaledBitmap(b, (b.width * f).toInt().coerceAtLeast(1), (b.height * f).toInt().coerceAtLeast(1), true)
    }

    private fun jpeg(b: Bitmap): ByteArray = ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()

    fun sizeLabel(bytes: Int): String = when {
        bytes >= 1024 * 1024 -> "%.1f MB".format(bytes / 1048576.0)
        bytes >= 1024 -> "${bytes / 1024} KB"
        else -> "$bytes B"
    }
}

@Composable
fun AttachmentStrip(items: List<Attachment>, onRemove: (Int) -> Unit) {
    if (items.isEmpty()) return
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 4.dp).testTag("attachment-strip"),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items.forEachIndexed { i, a ->
            InputChip(
                selected = false, onClick = { onRemove(i) },
                label = { Text("${a.name} · ${AttachmentReader.sizeLabel(a.sizeBytes)}", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                leadingIcon = { Icon(if (a.isImage) Icons.Outlined.Image else Icons.Outlined.AttachFile, null, Modifier.size(16.dp)) },
                trailingIcon = { Icon(Icons.Outlined.Close, "移除附件", Modifier.size(16.dp)) },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AttachSheet(onCamera: () -> Unit, onGallery: () -> Unit, onFile: () -> Unit, onClipboard: (() -> Unit)?, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(bottom = 24.dp)) {
            Text("添加附件（最多 4 个，共 10 MB）", Modifier.padding(horizontal = 20.dp, vertical = 8.dp), style = MaterialTheme.typography.titleSmall)
            ListItem(headlineContent = { Text("拍照") }, leadingContent = { Icon(Icons.Outlined.PhotoCamera, null) }, modifier = Modifier.clickable { onDismiss(); onCamera() })
            ListItem(headlineContent = { Text("从相册选图") }, leadingContent = { Icon(Icons.Outlined.Image, null) }, modifier = Modifier.clickable { onDismiss(); onGallery() })
            ListItem(headlineContent = { Text("选择文件") }, leadingContent = { Icon(Icons.Outlined.AttachFile, null) }, modifier = Modifier.clickable { onDismiss(); onFile() })
            if (onClipboard != null) ListItem(headlineContent = { Text("粘贴剪贴板里的图片") }, leadingContent = { Icon(Icons.Outlined.ContentPaste, null) }, modifier = Modifier.clickable { onDismiss(); onClipboard() })
        }
    }
}

/** Shown under the top bar when the session has a goal (F8). */
@Composable
fun GoalStrip(goal: String, onEdit: () -> Unit, onSend: () -> Unit, onClear: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, modifier = Modifier.fillMaxWidth().testTag("goal-strip")) {
        Row(Modifier.padding(start = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Flag, null, Modifier.size(16.dp))
            Text("目标：$goal", Modifier.weight(1f).padding(horizontal = 8.dp).clickable(onClick = onEdit), style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            TextButton(onClick = onSend) { Text("发给 Agent") }
            IconButton(onClick = onClear) { Icon(Icons.Outlined.Close, "清除目标", Modifier.size(18.dp)) }
        }
    }
}

@Composable
fun GoalDialog(initial: String, onSave: (String) -> Unit, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("会话目标") },
        text = {
            Column {
                Text("一句话写下这个会话要完成什么，会一直显示在顶部。", style = MaterialTheme.typography.bodySmall)
                OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth().padding(top = 8.dp).testTag("goal-input"), minLines = 2)
            }
        },
        confirmButton = { TextButton(onClick = { onSave(text) }, enabled = text.isNotBlank()) { Text("保存") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

/** "定时发送" (F5): daily at HH:MM or every N hours from then. */
@Composable
fun ScheduleDialog(initialPrompt: String, onSave: (prompt: String, hour: Int, minute: Int, everyHours: Int?) -> Unit, onDismiss: () -> Unit) {
    var prompt by remember { mutableStateOf(initialPrompt) }
    var hour by remember { mutableStateOf("9") }
    var minute by remember { mutableStateOf("00") }
    var repeat by remember { mutableStateOf(false) }
    var every by remember { mutableStateOf("4") }
    val h = hour.toIntOrNull()?.takeIf { it in 0..23 }
    val m = minute.toIntOrNull()?.takeIf { it in 0..59 }
    val n = every.toIntOrNull()?.takeIf { it in 1..24 }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("定时发送") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(prompt, { prompt = it }, Modifier.fillMaxWidth().testTag("schedule-prompt"), label = { Text("要发送的内容") }, minLines = 2)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(hour, { hour = it.filter(Char::isDigit).take(2) }, Modifier.weight(1f), label = { Text("时") }, singleLine = true,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number), isError = h == null)
                    OutlinedTextField(minute, { minute = it.filter(Char::isDigit).take(2) }, Modifier.weight(1f), label = { Text("分") }, singleLine = true,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number), isError = m == null)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(selected = !repeat, onClick = { repeat = false }, label = { Text("每天一次") })
                    FilterChip(selected = repeat, onClick = { repeat = true }, label = { Text("每隔几小时") })
                }
                if (repeat) OutlinedTextField(every, { every = it.filter(Char::isDigit).take(2) }, Modifier.fillMaxWidth(), label = { Text("间隔小时（1–24）") }, singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number), isError = n == null)
                Text("由手机按时发送，系统省电时可能晚几分钟；手机关机时会跳过。", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(prompt, h ?: 9, m ?: 0, if (repeat) n else null) },
                enabled = prompt.isNotBlank() && h != null && m != null && (!repeat || n != null),
            ) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

/** Speakable text: Markdown punctuation and code fences dropped. */
fun speakable(markdown: String): String = markdown
    .replace(Regex("```[\\s\\S]*?```"), "（代码已省略）")
    .replace(Regex("[*_`#>|]"), "")
    .replace(Regex("\\[(.*?)]\\((.*?)\\)"), "$1")
    .trim()
    .take(3900)
