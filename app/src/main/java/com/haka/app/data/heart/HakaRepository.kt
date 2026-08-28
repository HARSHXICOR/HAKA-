package com.haka.app.data.heart

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.haka.app.core.model.*
import com.haka.app.data.local.HakaDao
import com.haka.app.data.local.HakaStateEntity
import com.haka.app.data.local.QueuedTapEntity
import com.haka.app.widget.HakaWidget
import com.haka.app.work.TapRetryWorker
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.time.Instant
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import javax.inject.Inject
import javax.inject.Singleton
import dagger.hilt.android.qualifiers.ApplicationContext

interface HakaRepository {
    fun observeCachedState(): Flow<CachedHakaState?>
    suspend fun hasSession(): Boolean
    suspend fun ensureAnonymousSession(): String
    suspend fun continueWithGoogle()
    suspend fun linkGoogleIdentity()
    suspend fun bootstrap(): BootstrapResponse
    suspend fun createCouple(timezone: String, displayName: String?): CreateCoupleResponse
    suspend fun redeemInvite(code: String): RedeemInviteResponse
    suspend fun submitTap(coupleId: String, tapId: String = UUID.randomUUID().toString()): TapResult
    suspend fun queueTap(coupleId: String, tapId: String)
    suspend fun retryQueuedTaps(limit: Int = 20)
    suspend fun registerDevice(deviceId: String, token: String, enabled: Boolean)
    suspend fun sendThinkingOfYou(coupleId: String, eventId: String): ThinkingOfYouResult
    suspend fun recordThinkingPulse()
    suspend fun sendLoveNote(coupleId: String, body: String): LoveNoteResponse
    suspend fun getLoveNotes(coupleId: String): List<LoveNoteDto>
    suspend fun setMood(coupleId: String, mood: String): MoodResponse
    suspend fun getMoods(coupleId: String): MoodResponse
    fun watchForPartner(coupleId: String, onPaired: () -> Unit)
    fun stopPairingRealtime()
    fun startRealtime(coupleId: String)
    fun stopRealtime()
    suspend fun signOut()
}

@Singleton
class DefaultHakaRepository @Inject constructor(
    private val client: SupabaseClient,
    private val dao: HakaDao,
    @ApplicationContext private val appContext: Context,
) : HakaRepository {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var realtimeJob: Job? = null
    private var pairingJob: Job? = null

    override fun observeCachedState(): Flow<CachedHakaState?> = dao.observeState().map { it?.toModel() }

    override suspend fun hasSession(): Boolean = withContext(Dispatchers.IO) {
        client.auth.awaitInitialization()
        client.auth.currentSessionOrNull() != null
    }

    override suspend fun ensureAnonymousSession(): String = withContext(Dispatchers.IO) {
        // Auth restores its persisted Android session asynchronously. Waiting here
        // prevents a cold start from creating a second anonymous user prematurely.
        client.auth.awaitInitialization()
        if (client.auth.currentSessionOrNull() == null) client.auth.signInAnonymously()
        requireNotNull(client.auth.currentUserOrNull()?.id) { "Haka could not restore your session." }
    }

    override suspend fun continueWithGoogle() = withContext(Dispatchers.IO) {
        client.auth.signInWith(Google, redirectUrl = "haka://auth/callback")
    }

    override suspend fun linkGoogleIdentity() = withContext(Dispatchers.IO) {
        client.auth.linkIdentity(Google, redirectUrl = "haka://auth/callback")
        Unit
    }

    override suspend fun bootstrap(): BootstrapResponse = withContext(Dispatchers.IO) {
        ensureAnonymousSession()
        val response = client.functions.invoke("get-bootstrap")
        val bootstrap = response.body<BootstrapResponse>()
        saveBootstrap(bootstrap)
        bootstrap
    }

    override suspend fun createCouple(timezone: String, displayName: String?): CreateCoupleResponse = withContext(Dispatchers.IO) {
        val response = client.functions.invoke("create-couple", CreateCoupleRequest(timezone, displayName))
        response.body<CreateCoupleResponse>()
    }

    override suspend fun redeemInvite(code: String): RedeemInviteResponse = withContext(Dispatchers.IO) {
        val response = client.functions.invoke("redeem-invite", RedeemInviteRequest(code))
        response.body<RedeemInviteResponse>()
    }

    override suspend fun submitTap(coupleId: String, tapId: String): TapResult = withContext(Dispatchers.IO) {
        val response = client.functions.invoke("tap-heart", TapHeartRequest(coupleId, tapId))
        response.body<TapResult>().also { bootstrap() }
    }

    override suspend fun queueTap(coupleId: String, tapId: String) = withContext(Dispatchers.IO) {
        dao.purgeOld(System.currentTimeMillis() - 7 * 24 * 60 * 60 * 1000L)
        if (dao.queuedTaps(21).size >= 20) error("Too many offline taps are waiting to sync.")
        dao.enqueueTap(QueuedTapEntity(tapId, coupleId, System.currentTimeMillis()))
        scheduleTapRetry()
    }

    override suspend fun retryQueuedTaps(limit: Int) = withContext(Dispatchers.IO) {
        dao.queuedTaps(limit).forEach { queued ->
            runCatching { submitTap(queued.coupleId, queued.tapId) }
                .onSuccess { dao.deleteTap(queued.tapId) }
                .onFailure { dao.incrementAttempt(queued.tapId) }
        }
        bootstrap()
        Unit
    }

    override suspend fun registerDevice(deviceId: String, token: String, enabled: Boolean) = withContext(Dispatchers.IO) {
        client.functions.invoke("register-device", RegisterDeviceRequest(deviceId, token, enabled))
        Unit
    }

    override suspend fun sendThinkingOfYou(coupleId: String, eventId: String): ThinkingOfYouResult = withContext(Dispatchers.IO) {
        client.functions.invoke("thinking-of-you", ThinkingOfYouRequest(coupleId, eventId)).body()
    }

    override suspend fun recordThinkingPulse() = withContext(Dispatchers.IO) {
        dao.updateThinkingPulse(System.nanoTime(), System.currentTimeMillis())
    }

    override suspend fun sendLoveNote(coupleId: String, body: String): LoveNoteResponse = withContext(Dispatchers.IO) {
        client.functions.invoke("send-love-note", LoveNoteRequest(coupleId, body)).body()
    }

    override suspend fun getLoveNotes(coupleId: String): List<LoveNoteDto> = withContext(Dispatchers.IO) {
        client.functions.invoke("get-love-notes", LoveNoteRequest(coupleId, "")).body<LoveNotesResponse>().notes
    }

    override suspend fun setMood(coupleId: String, mood: String): MoodResponse = withContext(Dispatchers.IO) {
        client.functions.invoke("set-mood", MoodRequest(coupleId, mood)).body<MoodResponse>()
        getMoods(coupleId)
    }

    override suspend fun getMoods(coupleId: String): MoodResponse = withContext(Dispatchers.IO) {
        client.functions.invoke("get-mood", MoodRequest(coupleId, "")).body<MoodResponse>()
    }

    override fun watchForPartner(coupleId: String, onPaired: () -> Unit) {
        pairingJob?.cancel()
        pairingJob = scope.launch {
            val paired = AtomicBoolean(false)

            suspend fun checkPairing() {
                val bootstrap = runCatching { bootstrap() }.getOrNull()
                if (bootstrap?.couple?.members?.size == 2 && paired.compareAndSet(false, true)) {
                    onPaired()
                    stopPairingRealtime()
                }
            }

            val channel = client.realtime.channel("haka-pairing-$coupleId") { }
            launch {
                channel.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
                    table = "couple_members"; filter("couple_id", FilterOperator.EQ, coupleId)
                }.collect { checkPairing() }
            }
            channel.subscribe()

            // Realtime is preferred, but this backend check makes pairing reliable
            // when Android temporarily misses a Realtime event or reconnects late.
            while (currentCoroutineContext().isActive && !paired.get()) {
                delay(3_000)
                checkPairing()
            }
        }
    }

    override fun stopPairingRealtime() { pairingJob?.cancel(); pairingJob = null }

    override fun startRealtime(coupleId: String) {
        if (realtimeJob?.isActive == true) return
        realtimeJob = scope.launch {
            val channel = client.realtime.channel("haka-$coupleId") { }
            launch {
                channel.postgresChangeFlow<PostgresAction.Update>(schema = "public") {
                    table = "heart_state"; filter("couple_id", FilterOperator.EQ, coupleId)
                }.collect { change ->
                    val row = json.decodeFromJsonElement<HeartRow>(change.record)
                    dao.updateHeart(json.encodeToString(row.toDto()), System.currentTimeMillis())
                    HakaWidget().updateAll(appContext)
                }
            }
            launch {
                channel.postgresChangeFlow<PostgresAction.Update>(schema = "public") {
                    table = "daily_stats"; filter("couple_id", FilterOperator.EQ, coupleId)
                }.collect { change ->
                    val row = json.decodeFromJsonElement<DailyRow>(change.record)
                    val state = dao.state() ?: return@collect
                    val myTaps = row.tapsByUser[state.userId] ?: 0
                    dao.updateToday(json.encodeToString(TodayDto(row.day, row.tapsByUser, myTaps, (row.totalTaps - myTaps).coerceAtLeast(0), row.totalTaps, row.completed, row.completedAt?.let(::isoMillis))), System.currentTimeMillis())
                }
            }
            launch {
                channel.postgresChangeFlow<PostgresAction.Update>(schema = "public") {
                    table = "streaks"; filter("couple_id", FilterOperator.EQ, coupleId)
                }.collect { change ->
                    val row = json.decodeFromJsonElement<StreakRow>(change.record)
                    dao.updateStreak(json.encodeToString(StreakDto(row.current, row.longest, row.lastCompletedDate)), System.currentTimeMillis())
                }
            }
            launch {
                // Decay is authoritative and lazy on the backend. Materialize each
                // completed interval locally so the app and widget visibly change
                // without waiting for the next tap or network round trip.
                while (currentCoroutineContext().isActive) {
                    materializeLocalDecay()
                    delay(1_000)
                }
            }
            channel.subscribe()
        }
    }

    override fun stopRealtime() { realtimeJob?.cancel(); realtimeJob = null }

    override suspend fun signOut() = withContext(Dispatchers.IO) {
        stopRealtime()
        client.auth.signOut()
        dao.clearState()
    }

    private suspend fun saveBootstrap(value: BootstrapResponse) {
        val couple = value.couple
        dao.saveState(HakaStateEntity(
            userId = value.uid,
            displayName = value.user?.displayName,
            coupleId = couple?.coupleId,
            timezone = couple?.timezone,
            membersJson = json.encodeToString(couple?.members ?: emptyMap()),
            heartJson = couple?.state?.heart?.toLocalCache()?.let(json::encodeToString),
            todayJson = couple?.state?.today?.let(json::encodeToString),
            streakJson = couple?.state?.streak?.let(json::encodeToString),
            historyJson = couple?.state?.history?.let(json::encodeToString),
            thinkingPulse = 0L,
            syncedAtMillis = System.currentTimeMillis(),
        ))
        HakaWidget().updateAll(appContext)
    }

    private suspend fun materializeLocalDecay() {
        val state = dao.state() ?: return
        val rawHeart = state.heartJson?.let { runCatching { json.decodeFromString<HeartDto>(it) }.getOrNull() } ?: return
        val heart = rawHeart.toLocalCache()
        val now = System.currentTimeMillis()
        val intervals = ((now - heart.lastUpdatedAt).coerceAtLeast(0L) / LOCAL_DECAY_INTERVAL_MILLIS)
        val normalizedLastUpdated = heart.lastUpdatedAt + intervals * LOCAL_DECAY_INTERVAL_MILLIS
        if (intervals == 0L && normalizedLastUpdated == rawHeart.lastUpdatedAt) return
        val materialized = heart.copy(
            score = (heart.score - intervals * LOCAL_DECAY_AMOUNT).coerceAtLeast(0L).toInt(),
            lastUpdatedAt = normalizedLastUpdated,
        )
        dao.updateHeart(json.encodeToString(materialized), now)
        HakaWidget().updateAll(appContext)
    }

    private fun scheduleTapRetry() {
        val request = OneTimeWorkRequestBuilder<TapRetryWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(appContext).enqueueUniqueWork("haka-tap-retry", ExistingWorkPolicy.KEEP, request)
    }

    private fun HakaStateEntity.toModel(): CachedHakaState = CachedHakaState(
        userId = userId,
        displayName = displayName,
        coupleId = coupleId,
        timezone = timezone,
        members = json.decodeFromString(membersJson),
        heart = heartJson?.let { json.decodeFromString(it) },
        today = todayJson?.let { json.decodeFromString(it) },
        streak = streakJson?.let { json.decodeFromString(it) },
        history = historyJson?.let { json.decodeFromString(it) } ?: emptyList(),
        thinkingPulse = thinkingPulse,
        syncedAtMillis = syncedAtMillis,
    )

    private fun HeartRow.toDto() = HeartDto(score, maxScore, totalTaps, isoMillis(lastUpdatedAt), lastTapAt?.let(::isoMillis))
    private fun isoMillis(value: String): Long = Instant.parse(value).toEpochMilli()

    private fun HeartDto.toLocalCache() = copy(
        lastUpdatedAt = epochMillis(lastUpdatedAt),
        lastTapAt = lastTapAt?.let(::epochMillis),
    )

    private fun epochMillis(value: Long): Long = if (value in 1 until 10_000_000_000L) value * 1_000L else value

    private companion object {
        const val LOCAL_DECAY_INTERVAL_MILLIS = 30_000L
        const val LOCAL_DECAY_AMOUNT = 100L
    }
}
