package com.haka.app.work

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.haka.app.data.heart.HakaRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

/** Retries command ids already persisted locally; the server makes retries idempotent. */
@HiltWorker
class TapRetryWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted params: WorkerParameters,
    private val repository: HakaRepository,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result = runCatching {
        repository.retryQueuedTaps()
        Result.success()
    }.getOrElse { Result.retry() }
}
