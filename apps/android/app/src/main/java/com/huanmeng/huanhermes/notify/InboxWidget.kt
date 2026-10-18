package com.huanmeng.huanhermes.notify

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.huanmeng.huanhermes.HuanHermesApp
import com.huanmeng.huanhermes.MainActivity
import com.huanmeng.huanhermes.R

/** Home-screen widget (F7): approvals waiting; a tap opens "需要我". */
class InboxWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val n = runCatching { (context.applicationContext as HuanHermesApp).graph.inbox.state.value.visible.size }.getOrDefault(0)
        ids.forEach { manager.updateAppWidget(it, views(context, n)) }
    }

    companion object {
        private fun views(context: Context, n: Int) = RemoteViews(context.packageName, R.layout.widget_inbox).apply {
            setTextViewText(R.id.widget_count, if (n > 0) "$n 项待处理" else "没有待处理")
            val open = PendingIntent.getActivity(
                context, 8,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(ApprovalNotifications.EXTRA_OPEN_TAB, "inbox"),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            setOnClickPendingIntent(R.id.widget_root, open)
        }

        fun refresh(context: Context, count: Int) = runCatching {
            val m = AppWidgetManager.getInstance(context)
            val ids = m.getAppWidgetIds(ComponentName(context, InboxWidget::class.java))
            if (ids.isNotEmpty()) ids.forEach { m.updateAppWidget(it, views(context, count)) }
        }
    }
}
