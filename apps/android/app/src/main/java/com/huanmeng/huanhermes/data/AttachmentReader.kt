package com.huanmeng.huanhermes.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import com.huanmeng.huanhermes.core.agent.AgentAttachment
import com.huanmeng.huanhermes.core.agent.DocumentText
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/** Reads content:// files the user picked into [AgentAttachment]s, off the main thread. */
class AttachmentReader(private val context: Context) {
    @Volatile private var pdfReady = false

    data class Result(val attachment: AgentAttachment?, val error: String?)

    suspend fun read(uri: Uri): Result = withContext(Dispatchers.IO) {
        val cr = context.contentResolver
        var name = uri.lastPathSegment?.substringAfterLast('/') ?: "附件"
        var size = 0L
        runCatching {
            cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    c.getString(0)?.let { name = it }
                    if (!c.isNull(1)) size = c.getLong(1)
                }
            }
        }
        val mime = cr.getType(uri) ?: "application/octet-stream"
        if (size > MAX_BYTES) return@withContext Result(null, "$name 超过 ${MAX_BYTES / 1024 / 1024}MB")
        try {
            if (DocumentText.isImage(name, mime)) {
                val b64 = image(uri) ?: return@withContext Result(null, "$name 无法读取图片")
                return@withContext Result(AgentAttachment(name, "image/jpeg", imageBase64 = b64, size = size), null)
            }
            val bytes = cr.openInputStream(uri)?.use { it.readBytes() } ?: return@withContext Result(null, "$name 无法打开")
            val text = DocumentText.extract(name, mime, bytes, pdf = ::pdfText)
                ?: return@withContext Result(null, "$name 是不支持的格式")
            Result(AgentAttachment(name, mime, text = text.ifBlank { "（没有可提取的文字，可能是扫描件）" }, size = bytes.size.toLong()), null)
        } catch (e: OutOfMemoryError) {
            Result(null, "$name 太大")
        } catch (e: Exception) {
            Result(null, "$name：${e.message ?: e.javaClass.simpleName}")
        }
    }

    private fun pdfText(bytes: ByteArray): String {
        if (!pdfReady) { PDFBoxResourceLoader.init(context); pdfReady = true }
        PDDocument.load(bytes).use { doc ->
            val pages = doc.numberOfPages
            val stripper = PDFTextStripper().apply { startPage = 1; endPage = minOf(pages, 200) }
            val text = stripper.getText(doc)
            return if (pages > 200) "$text\n…（共 $pages 页，只读取了前 200 页）" else text
        }
    }

    /** Longest side ≤ 1568 px (what vision models use), JPEG q85. */
    private fun image(uri: Uri): String? {
        val cr = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1568) sample *= 2
        val bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return null
        val scale = 1568f / maxOf(bmp.width, bmp.height)
        val out = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
        val bo = ByteArrayOutputStream()
        out.compress(Bitmap.CompressFormat.JPEG, 85, bo)
        return Base64.encodeToString(bo.toByteArray(), Base64.NO_WRAP)
    }

    companion object { const val MAX_BYTES = 25L * 1024 * 1024 }
}
