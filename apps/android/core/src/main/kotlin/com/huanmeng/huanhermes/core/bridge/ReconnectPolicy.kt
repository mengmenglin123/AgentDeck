package com.huanmeng.huanhermes.core.bridge

import kotlin.random.Random

/**
 * Exponential backoff with no attempt cap: the client keeps trying until the
 * user disconnects or the Host rejects the credentials. Delay doubles from
 * [baseMs] up to [maxMs] with ±[jitter] spread so many phones don't stampede.
 */
class ReconnectPolicy(
    val baseMs: Long = 1_000,
    val maxMs: Long = 60_000,
    val jitter: Double = 0.2,
    private val random: Random = Random.Default,
) {
    init {
        require(baseMs > 0 && maxMs >= baseMs) { "invalid backoff bounds" }
        require(jitter in 0.0..1.0) { "jitter must be within 0..1" }
    }

    /** Delay before attempt number [attempt] (1-based). */
    fun delayFor(attempt: Int): Long {
        val exp = (attempt - 1).coerceIn(0, 30)
        val raw = (baseMs shl exp).coerceAtMost(maxMs).coerceAtLeast(baseMs)
        if (jitter == 0.0) return raw
        val spread = (raw * jitter).toLong()
        return (raw - spread + random.nextLong(spread * 2 + 1)).coerceIn(1, maxMs + spread)
    }
}
