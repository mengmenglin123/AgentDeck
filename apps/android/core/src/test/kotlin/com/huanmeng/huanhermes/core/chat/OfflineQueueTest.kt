package com.huanmeng.huanhermes.core.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class OfflineQueueTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun msg(host: String, sk: String, id: String, at: Long = 0) = QueuedMessage(host, sk, null, "text $id", id, at)

    @Test fun messagesBelongToTheirHostAndSession() = runBlocking {
        val q = OfflineQueue(FileQueueStorage(tmp.newFile("q.json")))
        q.enqueue(msg("h1", "s1", "a", 1)); q.enqueue(msg("h1", "s2", "b", 2)); q.enqueue(msg("h2", "s1", "c", 3))
        val sent = mutableListOf<String>()
        assertEquals(listOf("a"), q.flush("h1", "s1") { sent += it.msgId; true })
        assertEquals(listOf("a"), sent)
        assertEquals(listOf("b", "c"), q.items.value.map { it.msgId })
    }

    @Test fun loadMergesWithMemoryInsteadOfOverwriting() = runBlocking {
        val file = tmp.newFile("q.json")
        OfflineQueue(FileQueueStorage(file)).apply { enqueue(msg("h", "s", "disk", 1)) }
        val q = OfflineQueue(FileQueueStorage(file))
        q.enqueue(msg("h", "s", "typed-before-load", 2)) // happens before load() finishes
        q.load()
        assertEquals(listOf("disk", "typed-before-load"), q.items.value.map { it.msgId })
        assertEquals(listOf("disk", "typed-before-load"), FileQueueStorage(file).read().map { it.msgId })
    }

    @Test fun flushStopsAtFirstFailureKeepingOrder() = runBlocking {
        val q = OfflineQueue(FileQueueStorage(tmp.newFile("q.json")))
        listOf("1", "2", "3").forEachIndexed { i, id -> q.enqueue(msg("h", "s", id, i.toLong())) }
        assertEquals(listOf("1"), q.flush("h", "s") { it.msgId == "1" })
        assertEquals(listOf("2", "3"), q.pending("h", "s").map { it.msgId })
    }

    @Test fun fullQueueDuplicateAndBlankAndCorruptFile() = runBlocking {
        val file = tmp.newFile("q.json").apply { writeText("{corrupt") }
        val q = OfflineQueue(FileQueueStorage(file), maxSize = 2)
        q.load()
        assertTrue(q.items.value.isEmpty())
        assertTrue(q.enqueue(msg("h", "s", "1")))
        assertTrue(q.enqueue(msg("h", "s", "1")))
        assertTrue(q.enqueue(msg("h", "s", "2")))
        assertFalse(q.enqueue(msg("h", "s", "3")))
        assertFalse(q.enqueue(QueuedMessage("h", "s", null, "  ", "4", 0)))
        assertEquals(2, q.items.value.size)
    }
}
