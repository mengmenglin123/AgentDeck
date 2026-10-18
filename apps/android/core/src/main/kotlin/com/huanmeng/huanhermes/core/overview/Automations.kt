package com.huanmeng.huanhermes.core.overview

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * A prompt the phone sends into a session on a schedule ("定时提示"): daily at
 * [hour]:[minute], or every [everyHours] hours starting from that time. Works with
 * any Host, since it is just a normal message sent at the right moment.
 */
@Serializable
data class Automation(
    val id: String,
    val hostId: String,
    val sessionId: String,
    val sessionKey: String,
    val project: String? = null,
    val title: String,
    val prompt: String,
    val hour: Int = 9,
    val minute: Int = 0,
    /** null = once a day; 1..24 = every N hours. */
    val everyHours: Int? = null,
    val enabled: Boolean = true,
    val lastRunAt: Long = 0,
    val lastResult: String? = null,
) {
    val scheduleLabel: String get() {
        val hm = "%02d:%02d".format(hour, minute)
        return if (everyHours == null) "每天 $hm" else "从 $hm 起每 $everyHours 小时"
    }
}

object Automations {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val serializer = ListSerializer(Automation.serializer())

    fun encode(list: List<Automation>): String = json.encodeToString(serializer, list)
    fun decode(raw: String?): List<Automation> = if (raw.isNullOrBlank()) emptyList() else runCatching { json.decodeFromString(serializer, raw) }.getOrDefault(emptyList())

    /** Next fire time (epoch ms) strictly after [now]. */
    fun nextFire(a: Automation, now: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        val nowZ = ZonedDateTime.ofInstant(Instant.ofEpochMilli(now), zone)
        var t = nowZ.withHour(a.hour.coerceIn(0, 23)).withMinute(a.minute.coerceIn(0, 59)).withSecond(0).withNano(0)
        val step = a.everyHours?.coerceIn(1, 24)
        if (step == null) {
            if (!t.isAfter(nowZ)) t = t.plusDays(1)
        } else {
            // Anchor at today's start time (or yesterday's when it is still ahead), then step forward.
            if (t.isAfter(nowZ)) t = t.minusDays(1)
            while (!t.isAfter(nowZ)) t = t.plusHours(step.toLong())
        }
        return t.toInstant().toEpochMilli()
    }

    /** The soonest enabled automation and its fire time, if any. */
    fun soonest(list: List<Automation>, now: Long, zone: ZoneId = ZoneId.systemDefault()): Pair<Automation, Long>? =
        list.filter { it.enabled && it.prompt.isNotBlank() }.map { it to nextFire(it, now, zone) }.minByOrNull { it.second }

    /**
     * Automations due at [now]: their latest slot is at most [lateMs] ago (a phone that
     * was off for hours does not fire stale prompts) and has not run yet.
     */
    fun due(list: List<Automation>, now: Long, zone: ZoneId = ZoneId.systemDefault(), slackMs: Long = 90_000, lateMs: Long = 30 * 60_000): List<Automation> =
        list.filter { a ->
            a.enabled && a.prompt.isNotBlank() && run {
                val prev = previousFire(a, now + slackMs, zone)
                prev >= now - lateMs && a.lastRunAt < prev - slackMs
            }
        }

    fun previousFire(a: Automation, now: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        val next = nextFire(a, now, zone)
        val step = a.everyHours?.coerceIn(1, 24)?.toLong()?.times(3_600_000) ?: 86_400_000
        return next - step
    }
}
