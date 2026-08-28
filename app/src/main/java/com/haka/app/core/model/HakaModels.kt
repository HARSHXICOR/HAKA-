package com.haka.app.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable data class CreateCoupleRequest(val timezone: String, val displayName: String? = null)
@Serializable data class CreateCoupleResponse(val coupleId: String, val inviteCode: String, val expiresAt: Long)
@Serializable data class RedeemInviteRequest(val code: String)
@Serializable data class RedeemInviteResponse(val coupleId: String)
@Serializable data class TapHeartRequest(val coupleId: String, val tapId: String)
@Serializable data class RegisterDeviceRequest(val deviceId: String, val fcmToken: String, val notificationsEnabled: Boolean)
@Serializable data class ThinkingOfYouRequest(val coupleId: String, val eventId: String)
@Serializable data class ThinkingOfYouResult(
    val accepted: Boolean,
    val duplicate: Boolean = false,
    val eventId: String,
    val notificationSent: Boolean = false,
)
@Serializable data class LoveNoteRequest(val coupleId: String, val body: String)
@Serializable data class LoveNoteDto(
    val id: String,
    val coupleId: String,
    val senderUid: String,
    val recipientUid: String,
    val body: String,
    val createdAt: Long,
    val readAt: Long? = null,
)
@Serializable data class LoveNoteResponse(
    val id: String,
    val coupleId: String,
    val senderUid: String,
    val recipientUid: String,
    val body: String,
    val createdAt: Long,
    val readAt: Long? = null,
    val notificationSent: Boolean = false,
)
@Serializable data class LoveNotesResponse(val notes: List<LoveNoteDto> = emptyList())
@Serializable data class MoodRequest(val coupleId: String, val mood: String)
@Serializable data class MoodResponse(val day: String, val moods: Map<String, String> = emptyMap())

@Serializable data class BootstrapResponse(val uid: String, val user: UserDto? = null, val couple: CoupleDto? = null)
@Serializable data class UserDto(val displayName: String? = null, val coupleId: String? = null, val createdAt: Long? = null)
@Serializable data class CoupleDto(
    val coupleId: String,
    val members: Map<String, String>,
    val timezone: String,
    val status: String,
    val createdAt: Long? = null,
    val state: CoupleStateDto,
)
@Serializable data class CoupleStateDto(val heart: HeartDto, val today: TodayDto, val streak: StreakDto, val history: List<DailySummaryDto> = emptyList())
@Serializable data class HeartDto(val score: Int, val maxScore: Int, val totalTaps: Long, val lastUpdatedAt: Long, val lastTapAt: Long? = null)
@Serializable data class TodayDto(
    val date: String,
    val tapsByUser: Map<String, Int> = emptyMap(),
    val myTaps: Int = 0,
    val partnerTaps: Int = 0,
    val totalTaps: Int,
    val completed: Boolean,
    val completedAt: Long? = null,
)
@Serializable data class StreakDto(val current: Int, val longest: Int, val lastCompletedDate: String? = null)
@Serializable data class DailySummaryDto(
    val date: String,
    val tapsByUser: Map<String, Int> = emptyMap(),
    val myTaps: Int = 0,
    val partnerTaps: Int = 0,
    val totalTaps: Int,
    val completed: Boolean,
    val completedAt: Long? = null,
)
@Serializable data class TapResult(
    val accepted: Boolean,
    val duplicate: Boolean,
    val score: Int,
    val percentage: Double,
    val totalTaps: Long,
    val today: TapToday,
    val streak: StreakDto,
)
@Serializable data class TapToday(val myTaps: Int, val partnerTaps: Int, val totalTaps: Int, val completed: Boolean)

@Serializable data class HeartRow(
    @SerialName("couple_id") val coupleId: String,
    val score: Int,
    @SerialName("max_score") val maxScore: Int,
    @SerialName("total_taps") val totalTaps: Long,
    @SerialName("last_updated_at") val lastUpdatedAt: String,
    @SerialName("last_tap_at") val lastTapAt: String? = null,
)
@Serializable data class DailyRow(
    @SerialName("couple_id") val coupleId: String,
    val day: String,
    @SerialName("taps_by_user") val tapsByUser: Map<String, Int>,
    @SerialName("total_taps") val totalTaps: Int,
    val completed: Boolean,
    @SerialName("completed_at") val completedAt: String? = null,
)
@Serializable data class StreakRow(
    @SerialName("couple_id") val coupleId: String,
    @SerialName("current_count") val current: Int,
    @SerialName("longest_count") val longest: Int,
    @SerialName("last_completed_date") val lastCompletedDate: String? = null,
)

data class CachedHakaState(
    val userId: String,
    val displayName: String?,
    val coupleId: String?,
    val timezone: String?,
    val members: Map<String, String>,
    val heart: HeartDto?,
    val today: TodayDto?,
    val streak: StreakDto?,
    val history: List<DailySummaryDto> = emptyList(),
    val thinkingPulse: Long = 0L,
    val syncedAtMillis: Long,
)

sealed interface SyncStatus { data object Synced : SyncStatus; data object Syncing : SyncStatus; data object Offline : SyncStatus; data class Error(val message: String) : SyncStatus }
