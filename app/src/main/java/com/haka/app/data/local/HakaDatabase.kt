package com.haka.app.data.local

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "haka_state")
data class HakaStateEntity(
    @PrimaryKey
    val id: Int = 0,
    val userId: String,
    val displayName: String?,
    val coupleId: String?,
    val timezone: String?,
    val membersJson: String,
    val heartJson: String?,
    val todayJson: String?,
    val streakJson: String?,
    val historyJson: String? = null,
    val thinkingPulse: Long = 0L,
    val syncedAtMillis: Long,
)

@Entity(tableName = "queued_taps")
data class QueuedTapEntity(
    @PrimaryKey
    val tapId: String,
    val coupleId: String,
    val createdAtMillis: Long,
    val attempts: Int = 0,
)

@Dao interface HakaDao {
    @Query("SELECT * FROM haka_state WHERE id = 0") fun observeState(): Flow<HakaStateEntity?>
    @Query("SELECT * FROM haka_state WHERE id = 0") suspend fun state(): HakaStateEntity?
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun saveState(entity: HakaStateEntity)
    @Query("DELETE FROM haka_state") suspend fun clearState()
    @Query("UPDATE haka_state SET heartJson = :heartJson, syncedAtMillis = :syncedAt WHERE id = 0")
    suspend fun updateHeart(heartJson: String, syncedAt: Long)
    @Query("UPDATE haka_state SET todayJson = :todayJson, syncedAtMillis = :syncedAt WHERE id = 0")
    suspend fun updateToday(todayJson: String, syncedAt: Long)
    @Query("UPDATE haka_state SET streakJson = :streakJson, syncedAtMillis = :syncedAt WHERE id = 0")
    suspend fun updateStreak(streakJson: String, syncedAt: Long)
    @Query("UPDATE haka_state SET thinkingPulse = :pulse, syncedAtMillis = :syncedAt WHERE id = 0")
    suspend fun updateThinkingPulse(pulse: Long, syncedAt: Long)
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun enqueueTap(entity: QueuedTapEntity)
    @Query("SELECT * FROM queued_taps ORDER BY createdAtMillis ASC LIMIT :limit") suspend fun queuedTaps(limit: Int): List<QueuedTapEntity>
    @Query("DELETE FROM queued_taps WHERE tapId = :tapId") suspend fun deleteTap(tapId: String)
    @Query("UPDATE queued_taps SET attempts = attempts + 1 WHERE tapId = :tapId") suspend fun incrementAttempt(tapId: String)
    @Query("DELETE FROM queued_taps WHERE createdAtMillis < :beforeMillis") suspend fun purgeOld(beforeMillis: Long)
}

@Database(entities = [HakaStateEntity::class, QueuedTapEntity::class], version = 3, exportSchema = true)
abstract class HakaDatabase : RoomDatabase() { abstract fun hakaDao(): HakaDao }
