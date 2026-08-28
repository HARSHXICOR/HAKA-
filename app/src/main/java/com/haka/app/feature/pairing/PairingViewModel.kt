package com.haka.app.feature.pairing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.haka.app.data.heart.HakaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.time.ZoneId
import javax.inject.Inject

data class PairingUiState(val loading: Boolean = false, val inviteCode: String? = null, val expiresAt: Long? = null, val error: String? = null)

@HiltViewModel class PairingViewModel @Inject constructor(private val repository: HakaRepository) : ViewModel() {
    private val _state = MutableStateFlow(PairingUiState())
    val state: StateFlow<PairingUiState> = _state

    fun create(displayName: String, onPaired: () -> Unit) = viewModelScope.launch {
        _state.value = _state.value.copy(loading = true, error = null)
        runCatching { repository.createCouple(ZoneId.systemDefault().id, displayName.ifBlank { null }) }
            .onSuccess {
                _state.value = PairingUiState(inviteCode = it.inviteCode, expiresAt = it.expiresAt)
                repository.watchForPartner(it.coupleId, onPaired)
            }
            .onFailure { _state.value = PairingUiState(error = "Your Haka couldn't be created. Please try again.") }
    }

    fun redeem(rawCode: String, onSuccess: () -> Unit) = viewModelScope.launch {
        val code = rawCode.uppercase().filter { it.isLetterOrDigit() }.take(8).chunked(4).joinToString("-")
        _state.value = _state.value.copy(loading = true, error = null)
        runCatching { repository.redeemInvite(code) }
            .onSuccess { _state.value = PairingUiState(); onSuccess() }
            .onFailure { _state.value = PairingUiState(error = "This invite is invalid, expired, or already used.") }
    }
}
