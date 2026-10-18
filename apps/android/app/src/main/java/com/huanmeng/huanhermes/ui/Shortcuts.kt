package com.huanmeng.huanhermes.ui

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.huanmeng.huanhermes.MainActivity
import com.huanmeng.huanhermes.R
import com.huanmeng.huanhermes.core.chat.SessionRef
import com.huanmeng.huanhermes.notify.ApprovalNotifications

/** Launcher shortcuts (E3): "需要我" plus up to three pinned sessions. */
object Shortcuts {
    const val EXTRA_SESSION = "open_session"
    const val EXTRA_KEY = "open_session_key"
    const val EXTRA_PROJECT = "open_session_project"
    const val EXTRA_TITLE = "open_session_title"

    fun publish(context: Context, pinned: List<SessionRef>) = runCatching {
        val icon = IconCompat.createWithResource(context, R.mipmap.ic_launcher)
        val inbox = ShortcutInfoCompat.Builder(context, "inbox")
            .setShortLabel("需要我")
            .setLongLabel("需要我处理的审批")
            .setIcon(icon)
            .setIntent(Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW).putExtra(ApprovalNotifications.EXTRA_OPEN_TAB, "inbox"))
            .build()
        val sessions = pinned.take(3).map { r ->
            ShortcutInfoCompat.Builder(context, "s:" + r.id)
                .setShortLabel(r.title.take(24).ifBlank { "会话" })
                .setLongLabel(r.title.take(60).ifBlank { "会话" })
                .setIcon(icon)
                .setIntent(
                    Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
                        .putExtra(EXTRA_SESSION, r.id).putExtra(EXTRA_KEY, r.sessionKey)
                        .putExtra(EXTRA_PROJECT, r.project.orEmpty()).putExtra(EXTRA_TITLE, r.title),
                )
                .build()
        }
        ShortcutManagerCompat.setDynamicShortcuts(context, listOf(inbox) + sessions)
    }
}
