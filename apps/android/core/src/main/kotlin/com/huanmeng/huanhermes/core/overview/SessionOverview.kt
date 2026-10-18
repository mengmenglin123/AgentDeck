package com.huanmeng.huanhermes.core.overview

import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** What a session row needs from the user, most urgent first. Never shown by colour alone. */
enum class SessionStatus(val label: String) {
    NeedsYou("需要你"),
    Running("运行中"),
    Unread("有新结果"),
    Idle("空闲"),
    Offline("离线"),
}

object SessionOverview {
    /**
     * [lastSeenAt] is when this device last opened the session (epoch seconds);
     * a newer Host `updated_at` means an unread result.
     */
    fun statusOf(s: SessionInfo, lastSeenAt: Double?, hostOnline: Boolean): SessionStatus = when {
        s.pendingPermissions.isNotEmpty() || s.status == "needs_you" -> SessionStatus.NeedsYou
        !hostOnline -> SessionStatus.Offline
        s.running || s.status == "running" -> SessionStatus.Running
        isUnread(s, lastSeenAt) -> SessionStatus.Unread
        else -> SessionStatus.Idle
    }

    fun isUnread(s: SessionInfo, lastSeenAt: Double?): Boolean {
        val updated = s.updatedAt ?: return false
        // Never opened on this device: only results that carry a preview count as unread.
        if (lastSeenAt == null) return !s.preview.isNullOrBlank()
        return updated > lastSeenAt + 1.0
    }

    /** "刚刚" / "5 分钟前" / "3 小时前" / "昨天" / "3 天前" / "10月3日" / "2025年10月3日". */
    fun relativeTime(ts: Double?, nowSec: Double, zone: ZoneId = ZoneId.systemDefault()): String {
        if (ts == null || ts <= 0) return ""
        val diff = nowSec - ts
        if (diff < 60) return "刚刚"
        if (diff < 3600) return "${(diff / 60).toInt()} 分钟前"
        val then = Instant.ofEpochMilli((ts * 1000).toLong()).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli((nowSec * 1000).toLong()).atZone(zone).toLocalDate()
        val days = ChronoUnit.DAYS.between(then, today)
        return when {
            days <= 0L -> "${(diff / 3600).toInt()} 小时前"
            days == 1L -> "昨天"
            days < 7L -> "$days 天前"
            then.year == today.year -> "${then.monthValue}月${then.dayOfMonth}日"
            else -> "${then.year}年${then.monthValue}月${then.dayOfMonth}日"
        }
    }

    /** One line under the title: Host preview, else the last user message. */
    fun previewOf(s: SessionInfo, draft: String?): String = when {
        !draft.isNullOrBlank() -> "草稿：" + flat(draft)
        s.pendingPermissions.isNotEmpty() -> "等待批准：" + flat(s.pendingPermissions.first().prompt.ifBlank { "权限请求" })
        !s.preview.isNullOrBlank() -> flat(s.preview)
        !s.lastUser.isNullOrBlank() -> "你：" + flat(s.lastUser)
        else -> ""
    }

    private fun flat(text: String) = text.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ").take(160)
}

data class SessionRow(val session: SessionInfo, val status: SessionStatus, val pinned: Boolean, val archived: Boolean)

data class SessionGroup(val key: String, val title: String, val rows: List<SessionRow>)

/** Order inside each group; "needs you" always comes first. */
enum class SessionSort(val label: String) { Recent("最近活动"), Title("标题") }

object SessionGrouping {
    /**
     * Pinned first, then one group per project (most recently active first);
     * archived rows only when [showArchived]. [query] matches title, preview,
     * project and model, case-insensitively.
     */
    fun group(
        sessions: List<SessionInfo>,
        prefs: LocalSessionPrefs.Snapshot,
        hostOnline: Boolean,
        query: String = "",
        showArchived: Boolean = false,
        sort: SessionSort = SessionSort.Recent,
    ): List<SessionGroup> {
        val q = query.trim().lowercase()
        val rows = sessions.mapNotNull { s ->
            val archived = s.id in prefs.archived
            if (archived != showArchived) return@mapNotNull null
            if (q.isNotEmpty()) {
                val hay = listOfNotNull(s.displayTitle, s.preview, s.lastUser, s.project, s.model).joinToString("\n").lowercase()
                if (!hay.contains(q)) return@mapNotNull null
            }
            SessionRow(s, SessionOverview.statusOf(s, prefs.lastSeen[s.id], hostOnline), s.id in prefs.pinned, archived)
        }.sortedWith(
            when (sort) {
                SessionSort.Recent -> compareBy<SessionRow> { it.status != SessionStatus.NeedsYou }.thenByDescending { it.session.updatedAt ?: 0.0 }
                SessionSort.Title -> compareBy<SessionRow> { it.status != SessionStatus.NeedsYou }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.session.displayTitle }
            },
        )
        val pinned = rows.filter { it.pinned }
        val rest = rows.filterNot { it.pinned }
        val out = mutableListOf<SessionGroup>()
        if (pinned.isNotEmpty()) out += SessionGroup("pinned", "置顶", pinned)
        rest.groupBy { it.session.project.ifBlank { "默认" } }
            .entries
            .sortedByDescending { e -> e.value.maxOf { it.session.updatedAt ?: 0.0 } }
            .forEach { (project, list) -> out += SessionGroup("project:$project", project, list) }
        return out
    }

    fun archivedCount(sessions: List<SessionInfo>, prefs: LocalSessionPrefs.Snapshot) = sessions.count { it.id in prefs.archived }
}
