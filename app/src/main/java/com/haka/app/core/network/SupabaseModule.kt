package com.haka.app.core.network

import com.haka.app.BuildConfig
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.SupabaseClient
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object SupabaseModule {
    @Provides @Singleton fun client(): SupabaseClient {
        check(BuildConfig.SUPABASE_ANON_KEY.isNotBlank()) {
            "Add SUPABASE_ANON_KEY to local.properties. Never use a service-role key in Haka."
        }
        return createSupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY) {
            install(Auth) {
                scheme = "haka"
                host = "auth"
                defaultRedirectUrl = "haka://auth/callback"
            }
            install(Functions)
            install(Postgrest)
            install(Realtime)
        }
    }
}
