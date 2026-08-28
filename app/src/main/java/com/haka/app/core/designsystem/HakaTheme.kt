package com.haka.app.core.designsystem

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.LocalContentColor
import androidx.compose.ui.graphics.Color

private val HakaRose = Color(0xFFFF5C83)
private val HakaDark = Color(0xFF160D16)
private val Light = lightColorScheme(primary = HakaRose, secondary = Color(0xFF7A4B58), tertiary = Color(0xFF8E4E00))
private val Dark = darkColorScheme(
    primary = HakaRose,
    secondary = Color(0xFFFF9CB4),
    tertiary = Color(0xFFC45CFF),
    background = HakaDark,
    surface = Color(0xFF211420),
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable fun HakaTheme(dark: Boolean = true, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) Dark else Light) {
        CompositionLocalProvider(LocalContentColor provides Color.White, content = content)
    }
}
