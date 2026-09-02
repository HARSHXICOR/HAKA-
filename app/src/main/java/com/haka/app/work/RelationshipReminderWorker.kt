package com.haka.app.work

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.haka.app.data.heart.HakaRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

/** Performs the daily server-side anniversary check even when the app is not open. */
@HiltWorker
class RelationshipReminderWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted params: WorkerParameters,
    private val repository: HakaRepository,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result = runCatching {
        val coupleId = repository.bootstrap().couple?.coupleId
        if (coupleId != null) repository.getStory(coupleId)
        Result.success()
    }.getOrElse { Result.retry() }
}
