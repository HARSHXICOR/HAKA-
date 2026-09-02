package com.haka.app.feature.home

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Group
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.haka.app.core.model.CachedHakaState
import com.haka.app.core.model.SyncStatus
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import java.text.NumberFormat
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin

private val HomeBackgroundTop = Color(0xFF120C13)
private val HomeBackgroundBottom = Color(0xFF26101D)
private val Rose = Color(0xFFFF5C83)
private val SoftRose = Color(0xFFFF9CB4)
private val PartnerPurple = Color(0xFFC45CFF)
private val Panel = Color(0x1CFFFFFF)
private val PanelBorder = Color(0x2DFFFFFF)
private val Muted = Color(0xFFC9BEC7)

@Composable
fun HomeScreen(
    cached: CachedHakaState,
    offline: Boolean,
    viewModel: HomeViewModel = hiltViewModel(),
) {
    LaunchedEffect(cached.userId, cached.coupleId, cached.syncedAtMillis) { viewModel.bind(cached) }
    val state by viewModel.state.collectAsState()
    val current = state.cached ?: cached
    val heart = current.heart ?: return
    val haptic = LocalHapticFeedback.current
    val fraction = (heart.score.toFloat() / heart.maxScore.coerceAtLeast(1)).coerceIn(0f, 1f)
    val animatedFraction by animateFloatAsState(fraction, tween(750, easing = FastOutSlowInEasing), label = "heart fill")
    var pulsing by remember { mutableStateOf(false) }
    var tapBursts by remember { mutableStateOf<List<Long>>(emptyList()) }
    var celebrationId by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(state.pulse) {
        if (state.pulse != 0L) {
            pulsing = true
            tapBursts = tapBursts + state.pulse
            kotlinx.coroutines.delay(120)
            pulsing = false
            kotlinx.coroutines.delay(760)
            tapBursts = tapBursts - state.pulse
        }
    }
    LaunchedEffect(state.thinkingPulse) {
        if (state.thinkingPulse != 0L) {
            pulsing = true
            tapBursts = tapBursts + state.thinkingPulse
            kotlinx.coroutines.delay(150)
            pulsing = false
            kotlinx.coroutines.delay(760)
            tapBursts = tapBursts - state.thinkingPulse
        }
    }
    LaunchedEffect(state.celebration) {
        if (state.celebration != 0L) {
            celebrationId = state.celebration
            kotlinx.coroutines.delay(1_650)
            celebrationId = null
        }
    }
    val pulse by animateFloatAsState(if (pulsing) 1.035f else 1f, tween(180), label = "heart pulse")
    val isConnected = !offline && state.sync !is SyncStatus.Offline
    val today = current.today
    val percentage = (fraction * 100).roundToInt()

    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(HomeBackgroundTop, HomeBackgroundBottom))),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp)
                .padding(bottom = 120.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            HomeHeader(current)
            Spacer(Modifier.height(18.dp))
            ConnectionPill(isConnected)
            Spacer(Modifier.height(10.dp))
            ThinkingOfYouAction(
                enabled = isConnected,
                sending = state.thinkingSending,
                message = state.thinkingMessage,
                onClick = viewModel::thinkingOfYou,
            )
            Spacer(Modifier.height(8.dp))

            Box(Modifier.fillMaxWidth().height(360.dp), contentAlignment = Alignment.Center) {
                val particlePositions = listOf(Pair(-145, -75), Pair(150, -135), Pair(158, 12), Pair(-120, 145), Pair(130, 165))
                particlePositions.forEachIndexed { index, position ->
                    FloatingHeart(index.toLong(), position.first, position.second, if (index % 2 == 0) .78f else .55f)
                }
                HeartProgress(
                    fraction = animatedFraction,
                    percentage = percentage,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(330.dp)
                        .padding(horizontal = 18.dp)
                        .scale(pulse)
                        .semantics { contentDescription = "Shared heart, $percentage percent full. Tap to add energy." },
                    onTap = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        viewModel.tap()
                    },
                )
                tapBursts.forEach { TapBurst(it) }
            }

            Text(
                "${NumberFormat.getIntegerInstance().format(heart.score)} / ${NumberFormat.getIntegerInstance().format(heart.maxScore)}",
                color = SoftRose,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.AutoAwesome, null, tint = SoftRose, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(7.dp))
                Text("Keep tapping to fill our heart", color = Muted, style = MaterialTheme.typography.bodyLarge)
            }
            Spacer(Modifier.height(18.dp))
            TapStatsRow(today?.myTaps ?: 0, today?.totalTaps ?: 0, today?.partnerTaps ?: 0)
            Spacer(Modifier.height(16.dp))
            EncouragementCard()
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Verified, null, tint = Color(0xFF706A73), modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(7.dp))
                Text(
                    when {
                        offline || state.sync is SyncStatus.Offline -> "Offline · saved locally"
                        state.sync is SyncStatus.Syncing -> "Syncing now"
                        else -> "Synced just now"
                    },
                    color = Color(0xFFAAA1AA),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        celebrationId?.let { FullScreenHeartRain(it) }
    }
}

@Composable
private fun HomeHeader(cached: CachedHakaState) {
    Box(Modifier.fillMaxWidth().height(108.dp)) {
        AvatarBadge(cached.displayName, Modifier.align(Alignment.CenterStart))
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Haka", color = Color.White, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(3.dp))
            Text("🔥 ${cached.streak?.current ?: 0} day streak", color = Muted, style = MaterialTheme.typography.titleMedium)
        }
        Box(
            Modifier
                .align(Alignment.CenterEnd)
                .size(58.dp)
                .clip(CircleShape)
                .border(1.dp, PanelBorder, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Group, contentDescription = "Partner", tint = Color.White, modifier = Modifier.size(29.dp))
        }
    }
}

@Composable
private fun AvatarBadge(displayName: String?, modifier: Modifier = Modifier) {
    Box(modifier.size(58.dp).clip(CircleShape).background(Color(0xFF3C2430)).border(2.dp, Rose, CircleShape), contentAlignment = Alignment.Center) {
        if (displayName.isNullOrBlank()) {
            Icon(Icons.Rounded.Person, "Your profile", tint = Color.White, modifier = Modifier.size(31.dp))
        } else {
            Text(displayName.take(1).uppercase(), color = Color.White, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun ConnectionPill(connected: Boolean) {
    Row(
        Modifier
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0x241E0E1B))
            .border(1.dp, Color(0x7D8E506B), RoundedCornerShape(24.dp))
            .padding(horizontal = 22.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(18.dp).clip(CircleShape).background(if (connected) Color(0xFF56E77D) else Color(0xFFFFB15B)))
        Spacer(Modifier.width(12.dp))
        Text(if (connected) "Connected" else "Offline", color = Color.White, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun ThinkingOfYouAction(enabled: Boolean, sending: Boolean, message: String?, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Row(
            Modifier
                .clip(RoundedCornerShape(22.dp))
                .background(Color(0x302D142A))
                .border(1.dp, Rose.copy(alpha = if (enabled) .65f else .25f), RoundedCornerShape(22.dp))
                .clickable(enabled = enabled && !sending, onClick = onClick)
                .padding(horizontal = 18.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.AutoAwesome, null, tint = Rose.copy(alpha = if (enabled) 1f else .45f), modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(if (sending) "Sending…" else "Thinking of You", color = Color.White.copy(alpha = if (enabled) 1f else .45f), style = MaterialTheme.typography.labelLarge)
        }
        message?.let { Text(it, color = SoftRose, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 5.dp)) }
    }
}

@Composable
private fun HeartProgress(fraction: Float, percentage: Int, modifier: Modifier, onTap: () -> Unit) {
    val gravityTilt = rememberGravityTilt()
    val liquidTilt by animateFloatAsState(
        targetValue = gravityTilt,
        animationSpec = spring(dampingRatio = .48f, stiffness = 42f),
        label = "liquid gravity",
    )
    val liquidMotion = rememberInfiniteTransition(label = "liquid motion")
    val wavePhase by liquidMotion.animateFloat(
        initialValue = 0f,
        targetValue = (PI * 2).toFloat(),
        animationSpec = infiniteRepeatable(tween(1_650, easing = LinearEasing), RepeatMode.Restart),
        label = "liquid surface",
    )
    Box(modifier.clickable(onClick = onTap), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val heart = heartPath(size.width, size.height)
            drawPath(heart, brush = Brush.radialGradient(listOf(Color(0xFF542534), Color(0xFF180E17)), center = Offset(size.width * .5f, size.height * .42f), radius = size.maxDimension * .72f))
            clipPath(heart) {
                val waterY = size.height * (1f - fraction)
                drawRect(Brush.verticalGradient(listOf(Color(0xFF3E1728), Color(0xFF160D18))), topLeft = Offset(0f, 0f), size = Size(size.width, waterY.coerceAtLeast(0f)))
                val slope = liquidTilt * .58f
                val waveAmplitude = 5.dp.toPx() + abs(liquidTilt) * 8.dp.toPx()
                fun surfaceY(x: Float): Float {
                    val gravityLine = waterY + slope * (x - size.width * .5f)
                    val ripple = sin((x / size.width * PI * 2.3 + wavePhase).toFloat()) * waveAmplitude
                    return gravityLine + ripple
                }
                val surface = Path().apply {
                    moveTo(0f, surfaceY(0f))
                    for (step in 1..40) {
                        val x = size.width * step / 40f
                        lineTo(x, surfaceY(x))
                    }
                }
                val liquid = Path().apply {
                    addPath(surface)
                    lineTo(size.width, size.height)
                    lineTo(0f, size.height)
                    close()
                }
                drawPath(liquid, brush = Brush.verticalGradient(listOf(Color(0xFFFF7897), Color(0xFFE83E6E), Color(0xFF9F173F))))
                drawPath(surface, color = Color.White.copy(alpha = .32f), style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round))
                listOf(Triple(.23f, .67f, 5f), Triple(.31f, .72f, 3f), Triple(.65f, .66f, 3f), Triple(.73f, .75f, 5f), Triple(.43f, .8f, 2.5f)).forEach { (x, y, radius) ->
                    val bubble = Offset(size.width * x + liquidTilt * size.width * .035f, size.height * y + sin(wavePhase + x * 8f) * 3.dp.toPx())
                    if (bubble.y > surfaceY(bubble.x)) drawCircle(Color.White.copy(alpha = .2f), radius.dp.toPx(), bubble)
                }
            }
            drawPath(heart, brush = Brush.linearGradient(listOf(Color(0xFFFFD4DE), Color(0xFF93435D), Color(0xFFFFA4BA))), style = Stroke(width = 3.dp.toPx(), join = StrokeJoin.Round))
            val shine = Path().apply {
                moveTo(size.width * .18f, size.height * .36f)
                cubicTo(size.width * .15f, size.height * .22f, size.width * .22f, size.height * .12f, size.width * .34f, size.height * .11f)
            }
            drawPath(shine, color = Color.White.copy(alpha = .24f), style = Stroke(width = 13.dp.toPx(), cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("$percentage", color = Color.White, fontSize = MaterialTheme.typography.displayLarge.fontSize, fontWeight = FontWeight.Bold)
                Text("%", color = Color.White, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 12.dp))
            }
            Text("of our heart", color = Color.White, style = MaterialTheme.typography.titleLarge)
        }
    }
}

@Composable
private fun rememberGravityTilt(): Float {
    val context = LocalContext.current
    var tilt by remember { mutableFloatStateOf(0f) }
    DisposableEffect(context) {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = manager.getDefaultSensor(Sensor.TYPE_GRAVITY)
            ?: manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val listener = object : SensorEventListener {
            private var filtered = 0f
            override fun onSensorChanged(event: SensorEvent) {
                val normalized = (-event.values[0] / SensorManager.GRAVITY_EARTH).coerceIn(-.82f, .82f)
                filtered += (normalized - filtered) * .16f
                tilt = filtered
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        sensor?.let { manager.registerListener(listener, it, SensorManager.SENSOR_DELAY_GAME) }
        onDispose { manager.unregisterListener(listener) }
    }
    return tilt
}

private fun heartPath(width: Float, height: Float) = Path().apply {
    moveTo(width * .5f, height * .94f)
    cubicTo(width * .39f, height * .86f, width * .07f, height * .66f, width * .06f, height * .35f)
    cubicTo(width * .04f, height * .13f, width * .2f, height * .03f, width * .35f, height * .12f)
    cubicTo(width * .43f, height * .17f, width * .48f, height * .25f, width * .5f, height * .29f)
    cubicTo(width * .52f, height * .25f, width * .57f, height * .17f, width * .65f, height * .12f)
    cubicTo(width * .8f, height * .03f, width * .96f, height * .13f, width * .94f, height * .35f)
    cubicTo(width * .93f, height * .66f, width * .61f, height * .86f, width * .5f, height * .94f)
    close()
}

@Composable
private fun FloatingHeart(id: Long, x: Int, y: Int, alpha: Float) {
    val density = LocalDensity.current
    val transition = rememberInfiniteTransition(label = "ambient heart $id")
    val bob by transition.animateFloat(0f, 1f, infiniteRepeatable(tween((2300L + id * 130L).toInt()), RepeatMode.Reverse), label = "ambient bob")
    Text(
        "♥",
        color = Rose,
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier
            .offset { IntOffset(with(density) { x.dp.toPx().roundToInt() }, with(density) { (y - bob * 9).dp.toPx().roundToInt() }) }
            .alpha(alpha),
    )
}

@Composable
private fun TapBurst(id: Long) {
    val density = LocalDensity.current
    val progress by animateFloatAsState(1f, tween(850, easing = FastOutSlowInEasing), label = "tap burst $id")
    val particles = listOf(
        Triple(-78, -110, .72f), Triple(-36, -145, 1f), Triple(12, -124, .8f), Triple(64, -96, .65f),
        Triple(-104, -42, .55f), Triple(96, -35, .9f), Triple(25, -185, .58f),
    )
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        particles.forEachIndexed { index, particle ->
            val drift = if (index % 2 == 0) 1f else .82f
            Text(
                "♥",
                color = if (index % 3 == 0) SoftRose else Rose,
                fontSize = (17 + (index % 3) * 5).sp,
                modifier = Modifier
                    .offset {
                        IntOffset(
                            with(density) { (particle.first * progress).dp.toPx().roundToInt() },
                            with(density) { (particle.second * progress * drift).dp.toPx().roundToInt() },
                        )
                    }
                    .scale(1f + progress * particle.third)
                    .alpha((1f - progress).coerceIn(0f, 1f)),
            )
        }
    }
}

@Composable
private fun FullScreenHeartRain(id: Long) {
    val density = LocalDensity.current
    val progress by animateFloatAsState(1f, tween(1_500, easing = FastOutSlowInEasing), label = "full heart celebration $id")
    val particles = listOf(
        Triple(-165, -520, .8f), Triple(-125, -410, 1.1f), Triple(-82, -610, .7f), Triple(-40, -455, 1f),
        Triple(0, -560, .9f), Triple(48, -445, 1.15f), Triple(92, -625, .72f), Triple(140, -490, 1f),
        Triple(180, -350, .78f), Triple(-185, -280, .66f), Triple(120, -250, .72f), Triple(-18, -320, .9f),
    )
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        particles.forEachIndexed { index, particle ->
            Text(
                "♥",
                color = if (index % 3 == 0) SoftRose else Rose,
                fontSize = (24 + (index % 4) * 6).sp,
                modifier = Modifier
                    .offset {
                        val y = 280 + (particle.second - 280) * progress
                        IntOffset(with(density) { particle.first.dp.toPx().roundToInt() }, with(density) { y.dp.toPx().roundToInt() })
                    }
                    .scale(.7f + progress * particle.third)
                    .alpha((1f - progress).coerceIn(0f, 1f)),
            )
        }
    }
}

@Composable
private fun TapStatsRow(you: Int, today: Int, partner: Int) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        TapStatsCard("You", you, Rose, Modifier.weight(1.15f), line = true)
        TapStatsCard("Today", today, SoftRose, Modifier.weight(.82f), line = false)
        TapStatsCard("Partner", partner, PartnerPurple, Modifier.weight(1.15f), line = true)
    }
}

@Composable
private fun TapStatsCard(label: String, taps: Int, accent: Color, modifier: Modifier, line: Boolean) {
    Box(
        modifier
            .height(176.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(Panel)
            .border(1.dp, accent.copy(alpha = .25f), RoundedCornerShape(22.dp))
            .padding(15.dp),
    ) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    label,
                    color = accent,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = if (line) Modifier else Modifier.fillMaxWidth(),
                    textAlign = if (line) TextAlign.Start else TextAlign.Center,
                )
                Spacer(Modifier.weight(1f))
                if (line) Box(Modifier.size(40.dp).clip(CircleShape).background(accent.copy(alpha = .8f)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Person, null, tint = Color.White, modifier = Modifier.size(22.dp))
                }
            }
            Spacer(Modifier.height(9.dp))
            Text(
                "$taps",
                color = Color.White,
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                softWrap = false,
                modifier = if (line) Modifier else Modifier.fillMaxWidth(),
                textAlign = if (line) TextAlign.Start else TextAlign.Center,
            )
            Text(
                "taps",
                color = Muted,
                style = MaterialTheme.typography.bodyLarge,
                modifier = if (line) Modifier else Modifier.fillMaxWidth(),
                textAlign = if (line) TextAlign.Start else TextAlign.Center,
            )
            Spacer(Modifier.weight(1f))
            if (line) MiniLineChart(accent) else MiniBars(accent)
        }
    }
}

@Composable
private fun MiniLineChart(color: Color) {
    Canvas(Modifier.fillMaxWidth().height(40.dp)) {
        val path = Path().apply {
            moveTo(0f, size.height * .75f)
            cubicTo(size.width * .12f, size.height * .74f, size.width * .13f, size.height * .25f, size.width * .28f, size.height * .48f)
            cubicTo(size.width * .42f, size.height * .78f, size.width * .45f, size.height * .08f, size.width * .61f, size.height * .32f)
            cubicTo(size.width * .77f, size.height * .58f, size.width * .82f, size.height * .08f, size.width, size.height * .22f)
        }
        drawPath(path, color = color, style = Stroke(width = 2.2.dp.toPx(), cap = StrokeCap.Round))
        drawPath(Path().apply { addPath(path); lineTo(size.width, size.height); lineTo(0f, size.height); close() }, brush = Brush.verticalGradient(listOf(color.copy(alpha = .22f), Color.Transparent)))
    }
}

@Composable
private fun MiniBars(color: Color) {
    Canvas(Modifier.fillMaxWidth().height(42.dp)) {
        val heights = listOf(.3f, .58f, .8f, .55f, .92f, .62f, .45f, .67f, .4f)
        val gap = 5.dp.toPx()
        val barWidth = ((size.width - gap * (heights.size - 1)) / heights.size).coerceAtLeast(2f)
        heights.forEachIndexed { index, height ->
            val left = index * (barWidth + gap)
            drawRoundRect(
                color = color.copy(alpha = if (index == 4) .95f else .38f),
                topLeft = Offset(left, size.height * (1 - height)),
                size = Size(barWidth, size.height * height),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(5.dp.toPx(), 5.dp.toPx()),
            )
        }
    }
}

@Composable
private fun EncouragementCard() {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Color(0x1EFFFFFF))
            .border(1.dp, PanelBorder, RoundedCornerShape(22.dp))
            .padding(horizontal = 15.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(54.dp).clip(CircleShape).background(Color(0x243D1530)), contentAlignment = Alignment.Center) {
            Text("♥", color = Rose, style = MaterialTheme.typography.headlineLarge)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text("You're doing great!", color = Color.White, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text("Keep the love going 💕", color = Muted, style = MaterialTheme.typography.bodyLarge)
        }
        Icon(Icons.Rounded.ChevronRight, null, tint = Color.White.copy(alpha = .75f), modifier = Modifier.size(27.dp))
    }
}
