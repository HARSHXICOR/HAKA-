package com.haka.app.data.settings

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.hakaDataStore by preferencesDataStore("haka_settings")

@Singleton class SettingsRepository @Inject constructor(@ApplicationContext private val context: Context) {
    private val notificationsKey = booleanPreferencesKey("partner_notifications")
    val partnerNotifications: Flow<Boolean> = context.hakaDataStore.data.map { it[notificationsKey] ?: true }
    suspend fun setPartnerNotifications(enabled: Boolean) { context.hakaDataStore.edit { it[notificationsKey] = enabled } }
}
