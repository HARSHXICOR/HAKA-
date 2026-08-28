package com.haka.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight as GlanceFontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.haka.app.R
import com.haka.app.core.model.HeartDto
import com.haka.app.core.model.TodayDto
import com.haka.app.data.local.HakaDao
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import kotlinx.serialization.json.Json
import kotlin.math.max

@EntryPoint
@InstallIn(SingletonComponent::class)
interface WidgetEntryPoint { fun hakaDao(): HakaDao }

private data class WidgetState(
    val score: Int,
    val maxScore: Int,
    val totalTaps: Long,
    val yourTaps: Int,
    val partnerTaps: Int,
    val connected: Boolean,
) {
    val progress: Float get() = (score.toFloat() / maxScore.coerceAtLeast(1)).coerceIn(0f, 1f)
    val percent: Int get() = (progress * 100).toInt()
}

class HakaWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),
            DpSize(110.dp, 220.dp),
            DpSize(220.dp, 110.dp),
            DpSize(220.dp, 220.dp),
            DpSize(320.dp, 110.dp),
            DpSize(320.dp, 220.dp),
        ),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val dao = EntryPointAccessors.fromApplication(context, WidgetEntryPoint::class.java).hakaDao()
        val cached = dao.state()
        val json = Json { ignoreUnknownKeys = true }
        val heart = cached?.heartJson?.let { runCatching { json.decodeFromString<HeartDto>(it) }.getOrNull() }
        val today = cached?.todayJson?.let { runCatching { json.decodeFromString<TodayDto>(it) }.getOrNull() }
        val members = cached?.membersJson?.let { runCatching { json.decodeFromString<Map<String, String>>(it) }.getOrNull() }.orEmpty()
        val state = heart?.let {
            val lastUpdatedMillis = epochMillis(it.lastUpdatedAt)
            val intervals = ((System.currentTimeMillis() - lastUpdatedMillis).coerceAtLeast(0L) / 30_000L)
            val effectiveScore = max(0, it.score - (intervals * 100L).toInt())
            WidgetState(effectiveScore, it.maxScore, it.totalTaps, today?.myTaps ?: 0, today?.partnerTaps ?: 0, members.size >= 2)
        }
        provideContent { HakaWidgetContent(state) }
    }
}

@Composable
private fun HakaWidgetContent(state: WidgetState?) {
    val size = LocalSize.current
    val width = size.width
    val height = size.height
    when {
        state == null -> EmptyWidget()
        width < 130.dp && height < 130.dp -> CompactWidget(state)
        width < 130.dp -> TallWidget(state)
        height < 130.dp -> WideWidget(state)
        width < 260.dp -> SquareWidget(state)
        else -> LargeWidget(state)
    }
}

@Composable
private fun WidgetSurface(modifier: GlanceModifier = GlanceModifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxSize()
            .background(ColorProvider(Color(0xFF211126)))
            .cornerRadius(24.dp)
            .padding(14.dp),
        contentAlignment = Alignment.Center,
    ) { content() }
}

@Composable
private fun CompactWidget(state: WidgetState) {
    WidgetSurface {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
            WidgetHeart(42.dp)
            Spacer(GlanceModifier.height(4.dp))
            Text("${state.percent}%", style = widgetStyle(18.sp, Color.White, GlanceFontWeight.Bold))
            Text("♥ Haka", style = widgetStyle(10.sp, Color(0xFFFF9CB4), GlanceFontWeight.Bold))
        }
    }
}

@Composable
private fun TallWidget(state: WidgetState) {
    WidgetSurface {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
            Text("Haka", style = widgetStyle(18.sp, Color.White, GlanceFontWeight.Bold))
            Text(if (state.connected) "Connected" else "Waiting", style = widgetStyle(10.sp, Color(0xFFFF9CB4)))
            Spacer(GlanceModifier.height(8.dp))
            WidgetHeart(62.dp)
            Spacer(GlanceModifier.height(5.dp))
            Text("${state.percent}%", style = widgetStyle(20.sp, Color.White, GlanceFontWeight.Bold))
            Text("${state.score} / ${state.maxScore}", style = widgetStyle(10.sp, Color(0xFFE4C7DD)))
        }
    }
}

@Composable
private fun WideWidget(state: WidgetState) {
    WidgetSurface {
        Row(verticalAlignment = Alignment.CenterVertically) {
            WidgetHeart(70.dp)
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.fillMaxHeight(), verticalAlignment = Alignment.CenterVertically) {
                Text("Haka", style = widgetStyle(20.sp, Color.White, GlanceFontWeight.Bold))
                Text("${state.percent}% · ${state.score}/${state.maxScore}", style = widgetStyle(13.sp, Color(0xFFFF9CB4), GlanceFontWeight.Bold))
                Spacer(GlanceModifier.height(7.dp))
                ProgressBar(state)
            }
        }
    }
}

@Composable
private fun SquareWidget(state: WidgetState) {
    WidgetSurface {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
            Text("Haka", style = widgetStyle(20.sp, Color.White, GlanceFontWeight.Bold))
            Text(if (state.connected) "• Connected with love •" else "Waiting for connection", style = widgetStyle(11.sp, Color(0xFFFF9CB4)))
            Spacer(GlanceModifier.height(7.dp))
            WidgetHeart(76.dp)
            Spacer(GlanceModifier.height(3.dp))
            Text("${state.percent}%", style = widgetStyle(24.sp, Color.White, GlanceFontWeight.Bold))
            Text("♥ ${state.score} / ${state.maxScore}", style = widgetStyle(11.sp, Color(0xFFE4C7DD)))
            Spacer(GlanceModifier.height(7.dp))
            Row(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("You ${share(state.yourTaps, state.totalTaps)}%", style = widgetStyle(11.sp, Color(0xFFFF5D91), GlanceFontWeight.Bold))
                Spacer(GlanceModifier.width(16.dp))
                Text("Partner ${share(state.partnerTaps, state.totalTaps)}%", style = widgetStyle(11.sp, Color(0xFFA86BFF), GlanceFontWeight.Bold))
            }
        }
    }
}

@Composable
private fun LargeWidget(state: WidgetState) {
    WidgetSurface {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                WidgetHeart(92.dp)
                Spacer(GlanceModifier.height(4.dp))
                Text("${state.percent}%", style = widgetStyle(21.sp, Color.White, GlanceFontWeight.Bold))
            }
            Spacer(GlanceModifier.width(18.dp))
            Column(modifier = GlanceModifier.fillMaxHeight(), verticalAlignment = Alignment.CenterVertically) {
                Text("Haka", style = widgetStyle(22.sp, Color.White, GlanceFontWeight.Bold))
                Text(if (state.connected) "Connected with love" else "Waiting for connection", style = widgetStyle(13.sp, Color(0xFFC9B7C8)))
                Spacer(GlanceModifier.height(10.dp))
                Text("♥ ${state.score} / ${state.maxScore}", style = widgetStyle(15.sp, Color(0xFFFF7398), GlanceFontWeight.Bold))
                Spacer(GlanceModifier.height(7.dp))
                ProgressBar(state)
                Spacer(GlanceModifier.height(8.dp))
                Row {
                    Text("You ${share(state.yourTaps, state.totalTaps)}%", style = widgetStyle(12.sp, Color(0xFFFF5D91), GlanceFontWeight.Bold))
                    Spacer(GlanceModifier.width(24.dp))
                    Text("Partner ${share(state.partnerTaps, state.totalTaps)}%", style = widgetStyle(12.sp, Color(0xFFA86BFF), GlanceFontWeight.Bold))
                }
            }
        }
    }
}

@Composable
private fun EmptyWidget() {
    WidgetSurface {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
            Text("Haka", style = widgetStyle(18.sp, Color.White, GlanceFontWeight.Bold))
            Text("Open Haka to sync", style = widgetStyle(11.sp, Color(0xFFE4C7DD)))
        }
    }
}

@Composable
private fun WidgetHeart(size: androidx.compose.ui.unit.Dp) {
    Image(
        provider = ImageProvider(R.drawable.haka_widget_heart),
        contentDescription = "Haka shared heart",
        modifier = GlanceModifier.size(size),
    )
}

@Composable
private fun ProgressBar(state: WidgetState) {
    LinearProgressIndicator(
        progress = state.progress,
        modifier = GlanceModifier.fillMaxWidth().height(8.dp),
        color = ColorProvider(Color(0xFFFF4F83)),
        backgroundColor = ColorProvider(Color(0xFF38253D)),
    )
}

private fun widgetStyle(size: androidx.compose.ui.unit.TextUnit, color: Color, weight: GlanceFontWeight? = null) = TextStyle(
    color = ColorProvider(color),
    fontSize = size,
    fontWeight = weight,
)

private fun share(value: Int, total: Long): Int = if (total <= 0) 0 else ((value.toDouble() / total) * 100).toInt().coerceIn(0, 100)

private fun epochMillis(value: Long): Long = if (value in 1 until 10_000_000_000L) value * 1_000L else value

class HakaWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HakaWidget()
}
