package com.huanmeng.huanhermes.notify

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.huanmeng.huanhermes.HuanHermesApp
import java.util.concurrent.TimeUnit

/** Checks every Host for pending approvals while the app is closed (every ~15 min). */
class InboxWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as? HuanHermesApp ?: return Result.success()
        runCatching { app.graph.checkInboxAndNotify() }
        return Result.success()
    }

    companion object {
        private const val NAME = "inbox-check"

        fun schedule(context: Context, enabled: Boolean) = runCatching {
            val wm = WorkManager.getInstance(context)
            if (!enabled) { wm.cancelUniqueWork(NAME); return@runCatching }
            val req = PeriodicWorkRequestBuilder<InboxWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            wm.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }
    }
}
