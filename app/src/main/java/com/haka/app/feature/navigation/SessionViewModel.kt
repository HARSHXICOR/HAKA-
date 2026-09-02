package com.haka.app.feature.navigation

import android.content.Context
import android.provider.Settings
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.google.firebase.messaging.FirebaseMessaging
import com.haka.app.core.model.BootstrapResponse
import com.haka.app.core.model.CachedHakaState
import com.haka.app.core.model.SyncStatus
import com.haka.app.data.heart.HakaRepository
import com.haka.app.work.RelationshipReminderWorker
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit
import javax.inject.Inject

sealed interface SessionState {
    data object AuthRequired : SessionState
    data object Loading : SessionState
    data class Unpaired(val cached: CachedHakaState?) : SessionState
    data class Paired(val cached: CachedHakaState) : SessionState
    data class Failed(val message: String, val cached: CachedHakaState?) : SessionState
}

@HiltViewModel
class SessionViewModel @Inject constructor(
    private val repository: HakaRepository,
    @ApplicationContext private val appContext: Context,
) : ViewModel() {
    private val status = MutableStateFlow<SyncStatus>(SyncStatus.Syncing)
    val session: StateFlow<SessionState> = combine(repository.observeCachedState(), status) { cached, sync ->
        when {
            cached?.coupleId != null && cached.heart != null -> SessionState.Paired(cached)
            sync is SyncStatus.Error -> SessionState.Failed(sync.message, cached)
            cached != null -> SessionState.Unpaired(cached)
            sync is SyncStatus.Synced -> SessionState.AuthRequired
            else -> SessionState.Loading
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SessionState.Loading)

    init { initialize() }

    private fun initialize() = viewModelScope.launch {
        if (repository.hasSession()) refresh()
        else status.value = SyncStatus.Synced
    }

    fun continueAnonymously() = viewModelScope.launch {
        repository.ensureAnonymousSession()
        refresh()
    }

    fun continueWithGoogle() = viewModelScope.launch { repository.continueWithGoogle() }

    fun refresh() = viewModelScope.launch {
        status.value = SyncStatus.Syncing
        runCatching { repository.bootstrap() }
            .onSuccess { response ->
                response.couple?.coupleId?.let(repository::startRealtime)
                response.couple?.coupleId?.let { scheduleRelationshipReminders() }
                registerCurrentNotificationToken()
                status.value = SyncStatus.Synced
            }
            .onFailure { status.value = SyncStatus.Error("We couldn't sync Haka right now.") }
    }

    fun onPairingFinished() = refresh()

    private fun registerCurrentNotificationToken() {
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            val deviceId = Settings.Secure.getString(appContext.contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
            viewModelScope.launch { runCatching { repository.registerDevice(deviceId, token, true) } }
        }
    }

    private fun scheduleRelationshipReminders() {
        val request = PeriodicWorkRequestBuilder<RelationshipReminderWorker>(24, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(appContext).enqueueUniquePeriodicWork(
            "haka_relationship_reminders", ExistingPeriodicWorkPolicy.UPDATE, request,
        )
    }
}
