package com.haka.app.feature.love

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
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.MailOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.haka.app.core.model.CachedHakaState
import com.haka.app.core.model.LoveNoteDto
import com.haka.app.core.model.LoveNoteResponse
import com.haka.app.data.heart.HakaRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import java.util.UUID
import javax.inject.Inject

private val LoveBackgroundTop = Color(0xFF160C17)
private val LoveBackgroundBottom = Color(0xFF2A1022)
private val Rose = Color(0xFFFF5C83)
private val Purple = Color(0xFFB35AFF)
private val Green = Color(0xFF65E88A)
private val Muted = Color(0xFFC9BEC7)
private val Panel = Color(0x331F1822)
private val Line = Color(0x36FFFFFF)

data class LoveUiState(
    val notes: List<LoveNoteDto> = emptyList(),
    val moods: Map<String, String> = emptyMap(),
    val loading: Boolean = false,
    val sendingNote: Boolean = false,
    val thinkingSending: Boolean = false,
    val message: String? = null,
    val noteDialog: Boolean = false,
)

@HiltViewModel
class LoveViewModel @Inject constructor(private val repository: HakaRepository) : ViewModel() {
    private val _state = MutableStateFlow(LoveUiState())
    val state: StateFlow<LoveUiState> = _state

    fun load(coupleId: String) = viewModelScope.launch {
        _state.value = _state.value.copy(loading = true)
        val notes = runCatching { repository.getLoveNotes(coupleId) }.getOrDefault(emptyList())
        val moods = runCatching { repository.getMoods(coupleId).moods }.getOrDefault(emptyMap())
        _state.value = _state.value.copy(notes = notes, moods = moods, loading = false)
    }

    fun refresh(coupleId: String) = viewModelScope.launch {
        val notes = runCatching { repository.getLoveNotes(coupleId) }.getOrNull()
        val moods = runCatching { repository.getMoods(coupleId).moods }.getOrNull()
        _state.value = _state.value.copy(notes = notes ?: _state.value.notes, moods = moods ?: _state.value.moods)
    }

    fun showNoteDialog() { _state.value = _state.value.copy(noteDialog = true, message = null) }
    fun hideNoteDialog() { _state.value = _state.value.copy(noteDialog = false) }

    fun sendNote(coupleId: String, body: String) = viewModelScope.launch {
        if (body.trim().isEmpty() || _state.value.sendingNote) return@launch
        _state.value = _state.value.copy(sendingNote = true, message = null)
        runCatching { repository.sendLoveNote(coupleId, body.trim()) }
            .onSuccess { note ->
                _state.value = _state.value.copy(
                    notes = listOf(note.toDto()) + _state.value.notes,
                    sendingNote = false,
                    noteDialog = false,
                    message = if (note.notificationSent) "Love note sent 💌" else "Note saved; partner notifications are off.",
                )
            }
            .onFailure { _state.value = _state.value.copy(sendingNote = false, message = "Could not send the note right now.") }
    }

    fun sendThinkingOfYou(coupleId: String) = viewModelScope.launch {
        if (_state.value.thinkingSending) return@launch
        _state.value = _state.value.copy(thinkingSending = true, message = null)
        runCatching { repository.sendThinkingOfYou(coupleId, UUID.randomUUID().toString()) }
            .onSuccess { result ->
                _state.value = _state.value.copy(
                    thinkingSending = false,
                    message = if (result.notificationSent) "Thinking of You sent 💕" else "Sent; partner notifications are off.",
                )
            }
            .onFailure { _state.value = _state.value.copy(thinkingSending = false, message = "Could not send right now.") }
    }

    fun setMood(coupleId: String, mood: String) = viewModelScope.launch {
        runCatching { repository.setMood(coupleId, mood) }
            .onSuccess { response -> _state.value = _state.value.copy(moods = response.moods, message = "Mood updated for today.") }
            .onFailure { _state.value = _state.value.copy(message = "Could not update your mood right now.") }
    }

    private fun LoveNoteResponse.toDto() = LoveNoteDto(id, coupleId, senderUid, recipientUid, body, createdAt, readAt)
}

@Composable
fun LoveScreen(cached: CachedHakaState, viewModel: LoveViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(cached.coupleId) {
        cached.coupleId?.let { coupleId ->
            viewModel.load(coupleId)
            while (isActive) {
                delay(15_000)
                viewModel.refresh(coupleId)
            }
        }
    }
    val coupleId = cached.coupleId
    var noteText by rememberSaveable { mutableStateOf("") }

    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(LoveBackgroundTop, LoveBackgroundBottom)))) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Love", color = Color.White, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
            Text("A private space for the little things you share.", color = Muted, style = MaterialTheme.typography.titleMedium, lineHeight = 26.sp)
            state.message?.let { Text(it, color = Rose, style = MaterialTheme.typography.labelLarge, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }

            LoveActionCard(Icons.Rounded.AutoAwesome, Purple, if (state.thinkingSending) "Sending…" else "Thinking of You", "Send your partner a little reminder that they are on your mind.", "Send now", coupleId != null && !state.thinkingSending) { coupleId?.let(viewModel::sendThinkingOfYou) }
            LoveActionCard(Icons.Rounded.MailOutline, Rose, "Love Notes", "Write a private note for your partner. Notes are limited to 160 characters.", "Write a note", coupleId != null) { viewModel.showNoteDialog() }
            MoodCard(state.moods[cached.userId], cached.members.keys.firstOrNull { it != cached.userId }?.let(state.moods::get), coupleId != null) { mood -> coupleId?.let { viewModel.setMood(it, mood) } }

            if (state.notes.isNotEmpty()) {
                Text("Recent notes", color = Color.White, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                state.notes.forEach { LoveNoteCard(it, it.senderUid == cached.userId) }
            } else if (!state.loading) EmptyLoveNotes()
        }
    }

    if (state.noteDialog) {
        AlertDialog(
            onDismissRequest = viewModel::hideNoteDialog,
            title = { Text("Write a Love Note", color = Color.White) },
            text = { OutlinedTextField(value = noteText, onValueChange = { noteText = it.take(160) }, placeholder = { Text("Something sweet…", color = Muted) }, supportingText = { Text("${noteText.length}/160", color = Muted) }, minLines = 3, maxLines = 5, colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Rose, unfocusedBorderColor = Line, focusedTextColor = Color.White, unfocusedTextColor = Color.White)) },
            confirmButton = { TextButton(enabled = noteText.isNotBlank() && !state.sendingNote, onClick = { coupleId?.let { viewModel.sendNote(it, noteText) } }) { Text(if (state.sendingNote) "Sending…" else "Send 💌", color = Rose) } },
            dismissButton = { TextButton(onClick = viewModel::hideNoteDialog) { Text("Cancel", color = Muted) } },
            containerColor = Color(0xFF2A1727),
        )
    }
}

@Composable
private fun LoveActionCard(icon: androidx.compose.ui.graphics.vector.ImageVector, accent: Color, title: String, subtitle: String, buttonLabel: String, enabled: Boolean, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Panel).border(1.dp, accent.copy(alpha = .42f), RoundedCornerShape(24.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(54.dp).clip(CircleShape).background(accent.copy(alpha = .14f)), contentAlignment = Alignment.Center) { Icon(icon, null, tint = accent, modifier = Modifier.size(28.dp)) }; Spacer(Modifier.width(14.dp)); Text(title, color = Color.White, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        Text(subtitle, color = Muted, style = MaterialTheme.typography.bodyLarge, lineHeight = 25.sp)
        Button(onClick = onClick, enabled = enabled, colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = Color.White, disabledContainerColor = accent.copy(alpha = .25f)), shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth()) { Text(buttonLabel, fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun MoodCard(currentMood: String?, partnerMood: String?, enabled: Boolean, onMoodSelected: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Panel).border(1.dp, Green.copy(alpha = .35f), RoundedCornerShape(24.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(54.dp).clip(CircleShape).background(Green.copy(alpha = .14f)), contentAlignment = Alignment.Center) { Text("☀", fontSize = 27.sp) }; Spacer(Modifier.width(14.dp)); Column { Text("Daily Mood", color = Color.White, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Text("How are you feeling today?", color = Muted) } }
        MoodOptions(currentMood, enabled, onMoodSelected)
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color(0x221F1722)).padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Text("Partner", color = Muted, modifier = Modifier.weight(1f)); Text(partnerMood?.let(::moodLabel) ?: "Not shared yet", color = if (partnerMood == null) Muted else Purple, fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun MoodOptions(selected: String?, enabled: Boolean, onMoodSelected: (String) -> Unit) {
    val options = listOf("happy" to "😊", "loved" to "🥰", "calm" to "😌", "sad" to "😔", "missing" to "💭", "excited" to "🤩")
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { options.forEach { (value, emoji) -> Box(Modifier.size(42.dp).clip(CircleShape).background(if (selected == value) Rose.copy(alpha = .28f) else Color(0x221F1722)).border(1.dp, if (selected == value) Rose else Line, CircleShape).clickable(enabled = enabled) { onMoodSelected(value) }, contentAlignment = Alignment.Center) { Text(emoji, fontSize = 20.sp) } } }
}

@Composable
private fun LoveNoteCard(note: LoveNoteDto, sentByMe: Boolean) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(if (sentByMe) Rose.copy(alpha = .12f) else Purple.copy(alpha = .12f)).border(1.dp, if (sentByMe) Rose.copy(alpha = .3f) else Purple.copy(alpha = .3f), RoundedCornerShape(20.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Favorite, null, tint = if (sentByMe) Rose else Purple, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(if (sentByMe) "You" else "Your partner", color = if (sentByMe) Rose else Purple, fontWeight = FontWeight.Bold); Spacer(Modifier.weight(1f)); Text(DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(note.createdAt * 1000)), color = Muted, style = MaterialTheme.typography.labelSmall) }
        Text(note.body, color = Color.White, style = MaterialTheme.typography.bodyLarge, lineHeight = 24.sp)
    }
}

@Composable
private fun EmptyLoveNotes() {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Panel).border(1.dp, Line, RoundedCornerShape(20.dp)).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) { Icon(Icons.Rounded.Lock, null, tint = Muted, modifier = Modifier.size(28.dp)); Text("No love notes yet", color = Color.White, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold); Text("Your private notes will appear here.", color = Muted) }
}

private fun moodLabel(value: String): String = when (value) {
    "happy" -> "😊 Happy"
    "loved" -> "🥰 Loved"
    "calm" -> "😌 Calm"
    "sad" -> "😔 Sad"
    "missing" -> "💭 Missing you"
    "excited" -> "🤩 Excited"
    else -> value.replaceFirstChar(Char::uppercase)
}
