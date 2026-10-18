package com.huanmeng.huanhermes.core.overview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class AutomationsTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private fun at(h: Int, m: Int, day: Int = 19) = ZonedDateTime.of(2026, 10, day, h, m, 0, 0, zone).toInstant().toEpochMilli()
    private val daily = Automation("a", "h", "s", "sk", null, "t", "跑测试", hour = 9, minute = 30)

    @Test fun dailyAndEveryHours() {
        assertEquals(at(9, 30), Automations.nextFire(daily, at(8, 0), zone))
        assertEquals(at(9, 30, 20), Automations.nextFire(daily, at(9, 30), zone))
        val every = daily.copy(everyHours = 4)
        assertEquals(at(13, 30), Automations.nextFire(every, at(10, 0), zone))
        assertEquals(at(1, 30), Automations.nextFire(every, at(0, 10), zone))
    }

    @Test fun dueOnlyOncePerSlot() {
        assertEquals(listOf("a"), Automations.due(listOf(daily), at(9, 31), zone).map { it.id })
        assertTrue(Automations.due(listOf(daily.copy(lastRunAt = at(9, 30))), at(9, 31), zone).isEmpty())
        assertTrue(Automations.due(listOf(daily), at(12, 0), zone).isEmpty())
        val list = listOf(daily, daily.copy(id = "b", enabled = false))
        assertEquals(list, Automations.decode(Automations.encode(list)))
        assertEquals("每天 09:30", daily.scheduleLabel)
    }
}
