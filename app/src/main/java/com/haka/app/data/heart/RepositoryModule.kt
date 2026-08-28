package com.haka.app.data.heart

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module @InstallIn(SingletonComponent::class)
abstract class RepositoryModule { @Binds abstract fun bindRepository(impl: DefaultHakaRepository): HakaRepository }
