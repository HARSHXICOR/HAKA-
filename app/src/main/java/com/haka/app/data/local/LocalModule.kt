package com.haka.app.data.local

import android.content.Context
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module @InstallIn(SingletonComponent::class)
object LocalModule {
    private val migration1To2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE haka_state ADD COLUMN historyJson TEXT")
        }
    }
    private val migration2To3 = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE haka_state ADD COLUMN thinkingPulse INTEGER NOT NULL DEFAULT 0")
        }
    }

    @Provides @Singleton fun database(@ApplicationContext context: Context): HakaDatabase =
        Room.databaseBuilder(context, HakaDatabase::class.java, "haka.db")
            .addMigrations(migration1To2)
            .addMigrations(migration2To3)
            .fallbackToDestructiveMigration()
            .build()
    @Provides fun hakaDao(database: HakaDatabase): HakaDao = database.hakaDao()
}
