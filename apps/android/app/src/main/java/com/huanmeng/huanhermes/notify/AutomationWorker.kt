package com.huanmeng.huanhermes.notify

import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.huanmeng.huanhermes.HuanHermesApp
import com.huanmeng.huanhermes.R
import com.huanmeng.huanhermes.core.overview.Automations
import java.util.concurrent.TimeUnit

/** Sends due scheduled prompts, then re-arms itself for the next one (timing is approximate under Doze). */
class AutomationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as? HuanHermesApp ?: return Result.success()
        val now = System.currentTimeMillis()
        val due = Automations.due(app.graph.extras.automationsNow(), now)
        for (a in due) {
            val ok = runCatching { app.graph.sendPrompt(a.hostId, a.sessionKey, a.project, a.prompt) }.getOrDefault(false)
            app.graph.extras.updateAutomations { list ->
                list.map { if (it.id == a.id) it.copy(lastRunAt = now, lastResult = if (ok) "已发送" else "发送失败（Host 连不上）") else it }
            }
            notify(applicationContext, a.title, if (ok) "定时提示已发送：${a.prompt.take(60)}" else "定时提示没发出去：Host 连不上", a.id.hashCode())
        }
        schedule(applicationContext)
        return Result.success()
    }

    companion object {
        private const val NAME = "automations"

        suspend fun schedule(context: Context) = runCatching {
            val app = context.applicationContext as HuanHermesApp
            val wm = WorkManager.getInstance(context)
            val next = Automations.soonest(app.graph.extras.automationsNow(), System.currentTimeMillis())
            if (next == null) { wm.cancelUniqueWork(NAME); return@runCatching }
            val delay = (next.second - System.currentTimeMillis()).coerceAtLeast(15_000)
            val req = OneTimeWorkRequestBuilder<AutomationWorker>()
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            wm.enqueueUniqueWork(NAME, ExistingWorkPolicy.REPLACE, req)
        }

        private fun notify(context: Context, title: String, text: String, id: Int) = runCatching {
            if (!ApprovalNotifications.canPost(context)) return@runCatching
            RunNotifications.ensure(context)
            val n = NotificationCompat.Builder(context, RunNotifications.RUNS_CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_notify)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(id, n)
        }
    }
}
