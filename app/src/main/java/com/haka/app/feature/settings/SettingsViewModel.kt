package com.haka.app.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.haka.app.data.heart.HakaRepository
import com.haka.app.data.settings.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settings: SettingsRepository,
    private val haka: HakaRepository,
) : ViewModel() {
    val notifications: StateFlow<Boolean> = settings.partnerNotifications
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)

    fun setNotifications(enabled: Boolean) = viewModelScope.launch { settings.setPartnerNotifications(enabled) }
    fun linkGoogle() = viewModelScope.launch { haka.linkGoogleIdentity() }
    fun signOut(onDone: () -> Unit) = viewModelScope.launch { haka.signOut(); onDone() }
}
