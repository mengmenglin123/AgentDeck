package com.huanmeng.huanhermes.notify

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.huanmeng.huanhermes.HuanHermesApp
import com.huanmeng.huanhermes.core.overview.InboxItem
import com.huanmeng.huanhermes.core.protocol.Outbound
import kotlinx.coroutines.launch

/** Answers a permission from the notification shade, without opening the app. */
class ApprovalReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as? HuanHermesApp ?: return
        val hostId = intent.getStringExtra(K_HOST) ?: return
        val sessionKey = intent.getStringExtra(K_SESSION) ?: return
        val action = intent.getStringExtra(K_ACTION) ?: return
        val key = intent.getStringExtra(K_KEY)
        val nid = intent.getIntExtra(K_NID, 0)
        val project = intent.getStringExtra(K_PROJECT)
        val replyCtx = intent.getStringExtra(K_CTX)
        val title = intent.getStringExtra(K_TITLE) ?: "会话"
        val pending = goAsync()
        app.graph.scope.launch {
            try {
                ApprovalNotifications.showResult(context, nid, title, "正在发送…")
                val ok = app.graph.sendDecision(hostId, sessionKey, project, replyCtx, action)
                val verb = if (action.endsWith(":deny") || action == "deny") "已拒绝" else "已允许"
                ApprovalNotifications.showResult(context, nid, title, if (ok) verb else "发送失败，打开 App 重试")
                if (ok && key != null) app.graph.inbox.markAnswered(key)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private const val K_HOST = "host"; private const val K_SESSION = "sk"; private const val K_ACTION = "action"
        private const val K_KEY = "key"; private const val K_NID = "nid"; private const val K_PROJECT = "project"
        private const val K_CTX = "ctx"; private const val K_TITLE = "title"

        fun intent(context: Context, item: InboxItem, decision: String, nid: Int): PendingIntent {
            val action = Outbound.resolvePermissionAction(decision, item.permission.buttons)
            val i = Intent(context, ApprovalReceiver::class.java)
                .setAction("com.huanmeng.huanhermes.APPROVAL.$decision")
                .putExtra(K_HOST, item.hostId)
                .putExtra(K_SESSION, item.session.sessionKey)
                .putExtra(K_PROJECT, item.session.project.ifBlank { null })
                .putExtra(K_CTX, item.permission.replyCtx)
                .putExtra(K_ACTION, action)
                .putExtra(K_KEY, item.key)
                .putExtra(K_NID, nid)
                .putExtra(K_TITLE, item.session.displayTitle)
            val req = nid * 31 + decision.hashCode()
            return PendingIntent.getBroadcast(context, req, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
