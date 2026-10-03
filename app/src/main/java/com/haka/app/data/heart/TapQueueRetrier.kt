package com.haka.app.data.heart

import com.haka.app.data.local.QueuedTapEntity
import kotlinx.coroutines.CancellationException

/**
 * Replays persisted commands with their original tap IDs.
 * Reusing the ID is what lets the backend treat network retries idempotently.
 */
internal object TapQueueRetrier {
    suspend fun retry(
        queuedTaps: List<QueuedTapEntity>,
        submit: suspend (coupleId: String, tapId: String) -> Unit,
        delete: suspend (tapId: String) -> Unit,
        markFailed: suspend (tapId: String) -> Unit,
    ) {
        queuedTaps.forEach { queued ->
            try {
                submit(queued.coupleId, queued.tapId)
                delete(queued.tapId)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Throwable) {
                markFailed(queued.tapId)
            }
        }
    }
}
