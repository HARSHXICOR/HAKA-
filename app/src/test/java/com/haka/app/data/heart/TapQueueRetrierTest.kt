package com.haka.app.data.heart

import com.haka.app.data.local.QueuedTapEntity
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class TapQueueRetrierTest {
    @Test
    fun `retry preserves command ids and records each outcome`() = runTest {
        val queued = listOf(
            QueuedTapEntity(tapId = "tap-original-1", coupleId = "couple-a", createdAtMillis = 1),
            QueuedTapEntity(tapId = "tap-original-2", coupleId = "couple-a", createdAtMillis = 2, attempts = 1),
        )
        val submitted = mutableListOf<Pair<String, String>>()
        val deleted = mutableListOf<String>()
        val failed = mutableListOf<String>()

        TapQueueRetrier.retry(
            queuedTaps = queued,
            submit = { coupleId, tapId ->
                submitted += coupleId to tapId
                if (tapId == "tap-original-2") error("network unavailable")
            },
            delete = deleted::add,
            markFailed = failed::add,
        )

        assertEquals(
            listOf("couple-a" to "tap-original-1", "couple-a" to "tap-original-2"),
            submitted,
        )
        assertEquals(listOf("tap-original-1"), deleted)
        assertEquals(listOf("tap-original-2"), failed)
    }
}
