package com.haka.app.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.haka.app.core.model.CachedHakaState
import com.haka.app.core.model.SyncStatus
import com.haka.app.data.heart.HakaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import java.util.UUID
import javax.inject.Inject

data class HomeUiState(
    val cached: CachedHakaState? = null,
    val sync: SyncStatus = SyncStatus.Syncing,
    val pulse: Long = 0L,
    val thinkingPulse: Long = 0L,
    val celebration: Long = 0L,
    val message: String? = null,
    val thinkingSending: Boolean = false,
    val thinkingMessage: String? = null,
)

@HiltViewModel class HomeViewModel @Inject constructor(private val repository: HakaRepository) : ViewModel() {
    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state

    fun bind(cached: CachedHakaState) { _state.value = _state.value.copy(cached = cached, thinkingPulse = cached.thinkingPulse, sync = SyncStatus.Synced) }

    fun thinkingOfYou() = viewModelScope.launch {
        val current = _state.value.cached ?: return@launch
        val coupleId = current.coupleId ?: return@launch
        if (_state.value.thinkingSending) return@launch
        _state.value = _state.value.copy(thinkingSending = true, thinkingMessage = null, thinkingPulse = System.nanoTime())
        val result = runCatching { repository.sendThinkingOfYou(coupleId, UUID.randomUUID().toString()) }
        if (result.isSuccess) {
            val response = result.getOrThrow()
            val message = when {
                response.duplicate -> "Already sent 💕"
                response.notificationSent -> "Thinking of you sent 💕"
                else -> "Sent, but partner notifications are disabled."
            }
            _state.value = _state.value.copy(thinkingSending = false, thinkingMessage = message)
            delay(2_500)
            _state.value = _state.value.copy(thinkingMessage = null)
        } else {
            val error = result.exceptionOrNull()
            val raw = error?.message.orEmpty()
            val safeMessage = if (raw.contains("429") || raw.contains("limit", ignoreCase = true)) {
                "You’ve sent a lot of love—try again soon."
            } else {
                "Could not send right now. Please try again."
            }
            _state.value = _state.value.copy(thinkingSending = false, thinkingMessage = safeMessage)
            delay(2_500)
            _state.value = _state.value.copy(thinkingMessage = null)
        }
    }
    fun tap() = viewModelScope.launch {
        val state = _state.value.cached ?: return@launch
        val coupleId = state.coupleId ?: return@launch
        val tapId = UUID.randomUUID().toString()
        val wasFull = state.heart?.score == state.heart?.maxScore
        _state.value = _state.value.copy(pulse = System.nanoTime(), sync = SyncStatus.Syncing, message = null)
        runCatching { repository.submitTap(coupleId, tapId) }
            .onSuccess { result ->
                _state.value = _state.value.copy(
                    sync = SyncStatus.Synced,
                    celebration = if (!wasFull && result.percentage >= 100.0) System.nanoTime() else _state.value.celebration,
                )
            }
            .onFailure {
                runCatching { repository.queueTap(coupleId, tapId) }
                _state.value = _state.value.copy(sync = SyncStatus.Offline, message = "Tap saved and will sync when you reconnect.")
            }
    }
}
