package com.haka.app.feature.insights

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.ShowChart
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haka.app.core.model.CachedHakaState
import com.haka.app.core.model.DailySummaryDto
import com.haka.app.core.model.TodayDto
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

private val PageBackground = Color(0xFF160D16)
private val CardBackground = Color(0x331F1822)
private val CardBackgroundStrong = Color(0x5526192A)
private val Line = Color(0x36FFFFFF)
private val Muted = Color(0xFFB8ACB9)
private val Rose = Color(0xFFFF5C83)
private val Pink = Color(0xFFFF8EAB)
private val Purple = Color(0xFFB35AFF)
private val Green = Color(0xFF49E788)

@Composable
fun StatsScreen(cached: CachedHakaState) {
    val today = cached.today
    val total = today?.totalTaps ?: 0
    val you = today?.myTaps ?: 0
    val partner = today?.partnerTaps ?: 0
    val completion = if (today?.completed == true) 100 else 0
    InsightsPage { compact ->
        PageHeader("Stats", "Today, streaks, and shared progress appear here.")
        TodayCard(total, completion, today?.completed == true, compact = compact)
        StreakCard(cached.streak?.current ?: 0, cached.streak?.longest ?: 0, compact)
        SharedProgressCard(you, partner, total, compact)
        WeekCard(today, cached.history)
    }
}

@Composable
fun InsightsScreen(cached: CachedHakaState) {
    val today = cached.today
    val summaries = cached.history.ifEmpty { today?.let { listOf(it.toSummary()) } ?: emptyList() }
    InsightsPage { compact ->
        PageHeader("Insights", "Today, streaks, and shared progress appear here.")
        TodayCard(today?.totalTaps ?: 0, if (today?.completed == true) 100 else 0, today?.completed == true, compact = compact)
        StreakCard(cached.streak?.current ?: 0, cached.streak?.longest ?: 0, compact)
        SharedProgressCard(today?.myTaps ?: 0, today?.partnerTaps ?: 0, today?.totalTaps ?: 0, compact)
        WeekCard(today, cached.history)
        Text("Daily History", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        if (summaries.isNotEmpty()) summaries.take(90).forEach { HistoryRow(it, compact) } else EmptyHistory()
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.Top) {
            Icon(Icons.Rounded.Lock, null, tint = Muted, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(10.dp))
            Text("Only daily totals are shown to\nprotect your privacy.", color = Muted, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
fun HistoryScreen(cached: CachedHakaState) {
    val today = cached.today
    InsightsPage { compact ->
        PageHeader("History", "Haka keeps private daily summaries,\nnot a per-tap timeline.")
        TodayCard(today?.totalTaps ?: 0, if (today?.completed == true) 100 else 0, today?.completed == true, title = "Today's Summary", compact = compact)
        StreakCard(cached.streak?.current ?: 0, cached.streak?.longest ?: 0, compact)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Daily Summaries", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            FilterChip(selected = true, onClick = {}, label = { Text("All time") }, trailingIcon = { Icon(Icons.Rounded.ArrowDropDown, null) }, shape = RoundedCornerShape(22.dp), colors = FilterChipDefaults.filterChipColors(containerColor = CardBackgroundStrong, labelColor = Color.White), border = FilterChipDefaults.filterChipBorder(enabled = true, selected = true, borderColor = Line))
        }
        val summaries = cached.history.ifEmpty { today?.let { listOf(it.toSummary()) } ?: emptyList() }
        if (summaries.isNotEmpty()) summaries.take(90).forEach { HistoryRow(it, compact) } else EmptyHistory()
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.Top) {
            Icon(Icons.Rounded.Lock, null, tint = Muted, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(10.dp))
            Text("Only daily totals are shown to\nprotect your privacy.", color = Muted, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun InsightsPage(content: @Composable ColumnScope.(compact: Boolean) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(PageBackground, Color(0xFF20101C))))) {
        val compact = maxWidth < 390.dp
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = if (compact) 14.dp else 24.dp, vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) { content(compact) }
    }
}

@Composable
private fun PageHeader(title: String, subtitle: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp))
            Text(subtitle, color = Muted, style = MaterialTheme.typography.titleMedium, lineHeight = 26.sp)
        }
        Surface(shape = RoundedCornerShape(18.dp), color = Color.Transparent, border = androidx.compose.foundation.BorderStroke(1.dp, Color(0x553C263F))) { IconButton(onClick = {}) { Icon(Icons.Rounded.CalendarMonth, null, tint = Rose) } }
    }
}

@Composable
private fun TodayCard(total: Int, completion: Int, completed: Boolean, title: String = "Today", compact: Boolean = false) {
    InsightCard(borderColor = Rose) {
        if (compact) {
            Row(verticalAlignment = Alignment.CenterVertically) { CircleIcon(Icons.Rounded.FavoriteBorder, Rose, 58.dp); Spacer(Modifier.width(14.dp)); Text(title, color = Pink, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
            TodayMetrics(total, completion, completed)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) { CircleIcon(Icons.Rounded.FavoriteBorder, Rose, 72.dp); Spacer(Modifier.width(24.dp)); TodayMetrics(total, completion, completed, Modifier.weight(1f), title) }
        }
    }
}

@Composable
private fun TodayMetrics(total: Int, completion: Int, completed: Boolean, modifier: Modifier = Modifier, title: String? = null) {
    Column(modifier) {
        if (title != null) { Text(title, color = Pink, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Spacer(Modifier.height(8.dp)) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("$total taps", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, maxLines = 1)
            Spacer(Modifier.width(10.dp)); Text("•", color = Muted, style = MaterialTheme.typography.titleLarge); Spacer(Modifier.width(10.dp))
            Text(if (completed) "Completed" else "In progress", color = if (completed) Green else Pink, style = MaterialTheme.typography.titleMedium, maxLines = 1)
        }
        Spacer(Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            LinearProgressIndicator(progress = { completion / 100f }, modifier = Modifier.weight(1f).height(9.dp).clip(RoundedCornerShape(8.dp)), color = Pink, trackColor = Color(0x332F2331))
            Spacer(Modifier.width(14.dp)); Text("$completion%", color = Pink, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun StreakCard(current: Int, longest: Int, compact: Boolean) {
    InsightCard {
        if (compact) {
            StreakMetric(Icons.Rounded.LocalFireDepartment, Color(0xFFFF714E), "Current streak", current, "Keep it going! 🔥")
            HorizontalDivider(color = Line)
            StreakMetric(Icons.Rounded.EmojiEvents, Purple, "Longest streak", longest, "Your best so far! 🏆")
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                StreakMetric(Icons.Rounded.LocalFireDepartment, Color(0xFFFF714E), "Current streak", current, "Keep it going! 🔥", Modifier.weight(1f))
                Box(Modifier.width(1.dp).height(68.dp).background(Line));
                StreakMetric(Icons.Rounded.EmojiEvents, Purple, "Longest streak", longest, "Your best so far! 🏆", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun StreakMetric(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, label: String, value: Int, hint: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) { CircleIcon(icon, color, 58.dp); Spacer(Modifier.width(12.dp)); Column { Text(label, color = Muted, style = MaterialTheme.typography.titleMedium); Text("$value days", color = color, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold); Text(hint, color = Muted, style = MaterialTheme.typography.bodyMedium) } }
}

@Composable
private fun SharedProgressCard(you: Int, partner: Int, total: Int, compact: Boolean) {
    val youPercent = if (total == 0) 50 else (you * 100f / total).roundToInt()
    InsightCard(borderColor = Color(0x664B294D)) {
        Text("Today's Progress", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Spacer(Modifier.height(18.dp))
        if (compact) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Contribution("You", you, youPercent, Rose, Modifier); Contribution("Partner", partner, 100 - youPercent, Purple, Modifier, true) }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { DonutChart(youPercent, Modifier.size(130.dp)) }
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Contribution("You", you, youPercent, Rose, Modifier.weight(1f)); DonutChart(youPercent, Modifier.size(138.dp)); Contribution("Partner", partner, 100 - youPercent, Purple, Modifier.weight(1f), true) }
        }
        Spacer(Modifier.height(14.dp)); Text("You and your partner are filling the heart together 💕", color = Muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun Contribution(label: String, taps: Int, percent: Int, color: Color, modifier: Modifier, rightAligned: Boolean = false) {
    Column(modifier, horizontalAlignment = if (rightAligned) Alignment.End else Alignment.Start) { Text(label, color = color, style = MaterialTheme.typography.titleMedium); Text("$taps", color = color, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold); Text("taps", color = Muted); Surface(shape = RoundedCornerShape(18.dp), color = color.copy(alpha = .2f)) { Text("$percent%", color = color, modifier = Modifier.padding(horizontal = 12.dp, vertical = 5.dp), fontWeight = FontWeight.Bold) } }
}

@Composable
private fun DonutChart(youPercent: Int, modifier: Modifier) {
    Canvas(modifier) {
        val stroke = 25.dp.toPx(); val diameter = size.minDimension - stroke; val topLeft = Offset((size.width - diameter) / 2, (size.height - diameter) / 2)
        drawArc(Rose, -90f, youPercent * 3.6f, false, topLeft, Size(diameter, diameter), style = Stroke(stroke, cap = StrokeCap.Butt))
        drawArc(Purple, -90f + youPercent * 3.6f, (100 - youPercent) * 3.6f, false, topLeft, Size(diameter, diameter), style = Stroke(stroke, cap = StrokeCap.Butt))
        drawCircle(Color(0xFF211420), radius = diameter / 2 - stroke / 2, center = center)
        drawCircle(Rose, radius = 17.dp.toPx(), center = center, style = Stroke(4.dp.toPx()))
    }
}

@Composable
private fun WeekCard(today: TodayDto?, history: List<DailySummaryDto>) {
    val points = weekPoints(today, history)
    val maxValue = points.maxOfOrNull { it.taps }?.coerceAtLeast(1) ?: 1
    InsightCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("This Week", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Spacer(Modifier.weight(1f)); Surface(shape = RoundedCornerShape(20.dp), color = CardBackgroundStrong, border = androidx.compose.foundation.BorderStroke(1.dp, Line)) { Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Text("7 Days"); Icon(Icons.Rounded.ArrowDropDown, null) } } }
        Spacer(Modifier.height(22.dp))
        Row(Modifier.fillMaxWidth().height(170.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.Bottom) {
            points.forEach { point -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Bottom, modifier = Modifier.weight(1f).fillMaxHeight()) { if (point.taps > 0) Text(point.taps.toString(), color = Color.White, style = MaterialTheme.typography.labelMedium, maxLines = 1); Spacer(Modifier.height(6.dp)); Box(Modifier.width(22.dp).height((point.taps.toFloat() / maxValue * 120f).coerceAtLeast(4f).dp).clip(RoundedCornerShape(topStart = 7.dp, topEnd = 7.dp)).background(if (point.isToday) Rose else Purple.copy(alpha = .7f))); Spacer(Modifier.height(8.dp)); Text(point.label, color = if (point.isToday) Pink else Muted, style = MaterialTheme.typography.labelMedium, maxLines = 1) } }
        }
        val average = if (points.isEmpty()) 0 else points.sumOf { it.taps } / points.size
        Spacer(Modifier.height(14.dp)); Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color(0x221F1722)).padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ShowChart, null, tint = Rose); Spacer(Modifier.width(10.dp)); Text(if (average > 0) "Nice! Your shared heart is active." else "Tap together to start this week's progress.", color = Muted, modifier = Modifier.weight(1f)); Text("Avg: $average taps", color = Pink, fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun HistoryRow(summary: DailySummaryDto, compact: Boolean) {
    val date = runCatching { LocalDate.parse(summary.date) }.getOrNull()
    val day = date?.dayOfMonth?.toString() ?: summary.date.takeLast(2)
    val month = date?.format(DateTimeFormatter.ofPattern("MMM", Locale.getDefault())) ?: ""
    InsightCard { Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(if (compact) 52.dp else 60.dp), shape = CircleShape, color = Rose.copy(alpha = .18f), border = androidx.compose.foundation.BorderStroke(1.dp, Rose.copy(alpha = .55f))) { Box(contentAlignment = Alignment.Center) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(day, color = Color.White, fontWeight = FontWeight.Bold); if (month.isNotEmpty()) Text(month, color = Color.White, style = MaterialTheme.typography.labelSmall) } } }; Spacer(Modifier.width(if (compact) 12.dp else 18.dp)); Column(Modifier.weight(1f)) { Text("${summary.totalTaps} taps", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1); Text(if (summary.completed) "Completed" else "In progress", color = if (summary.completed) Green else Pink, style = MaterialTheme.typography.titleMedium) }; Icon(Icons.Rounded.Favorite, null, tint = Rose, modifier = Modifier.size(28.dp)); Icon(Icons.Rounded.ChevronRight, null, tint = Muted, modifier = Modifier.size(28.dp)) } }
}

@Composable private fun EmptyHistory() { InsightCard { Text("No daily summaries yet", style = MaterialTheme.typography.titleMedium); Text("Your completed days will appear here.", color = Muted) } }

@Composable
private fun InsightCard(borderColor: Color = Line, content: @Composable ColumnScope.() -> Unit) { Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(CardBackground).border(1.dp, borderColor, RoundedCornerShape(24.dp)).padding(22.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content) }

@Composable
private fun CircleIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, size: androidx.compose.ui.unit.Dp) { Surface(Modifier.size(size), shape = CircleShape, color = tint.copy(alpha = .12f), border = androidx.compose.foundation.BorderStroke(1.dp, tint.copy(alpha = .45f))) { Box(contentAlignment = Alignment.Center) { Icon(icon, null, tint = tint, modifier = Modifier.size(size * .52f)) } } }

private data class WeekPoint(val label: String, val taps: Int, val isToday: Boolean)

private fun weekPoints(today: TodayDto?, history: List<DailySummaryDto>): List<WeekPoint> {
    val current = today?.date?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: return emptyList()
    val byDate = (history + listOfNotNull(today?.toSummary())).associateBy { runCatching { LocalDate.parse(it.date) }.getOrNull() }
    return (6L downTo 0L).map { offset ->
        val date = current.minusDays(offset)
        WeekPoint(if (date == current) "Today" else date.format(DateTimeFormatter.ofPattern("EEE", Locale.getDefault())), byDate[date]?.totalTaps ?: 0, date == current)
    }
}

private fun TodayDto.toSummary() = DailySummaryDto(date, tapsByUser, myTaps, partnerTaps, totalTaps, completed, completedAt)
