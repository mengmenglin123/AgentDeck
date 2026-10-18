package com.huanmeng.huanhermes.notify

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.huanmeng.huanhermes.HuanHermesApp
import com.huanmeng.huanhermes.MainActivity

/** Quick Settings tile: how many approvals wait; a tap opens "需要我" (E3). */
class InboxTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        runCatching {
            val n = (application as HuanHermesApp).graph.inbox.state.value.visible.size
            qsTile?.apply {
                state = if (n > 0) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
                label = "需要我"
                if (Build.VERSION.SDK_INT >= 29) subtitle = if (n > 0) "$n 项待处理" else "没有待处理"
                updateTile()
            }
        }
    }

    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(ApprovalNotifications.EXTRA_OPEN_TAB, "inbox")
        runCatching {
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 7, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            } else {
                @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
                startActivityAndCollapse(intent)
            }
        }
    }

    companion object {
        fun refresh(context: Context) = runCatching {
            requestListeningState(context, ComponentName(context, InboxTileService::class.java))
        }
    }
}
