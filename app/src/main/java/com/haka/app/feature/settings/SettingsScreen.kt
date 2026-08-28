package com.haka.app.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Group
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Logout
import androidx.compose.material.icons.rounded.NotificationsNone
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.haka.app.core.model.CachedHakaState

private val SettingsBg = Color(0xFF160D16)
private val SettingsCard = Color(0x331F1822)
private val SettingsLine = Color(0x36FFFFFF)
private val SettingsMuted = Color(0xFFB8ACB9)
private val SettingsRose = Color(0xFFFF5C83)
private val SettingsPurple = Color(0xFFB35AFF)
private val SettingsGreen = Color(0xFF8DF46E)
private val PinkTrack = Color(0xFFFF8FAF)

@Composable
fun SettingsScreen(cached: CachedHakaState, onSignOut: () -> Unit, viewModel: SettingsViewModel = hiltViewModel()) {
    val notifications by viewModel.notifications.collectAsState()
    Column(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(SettingsBg, Color(0xFF20101C)))).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(15.dp)) {
        Text("Settings", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
        SectionLabel("Account")
        SettingsRow(Icons.Rounded.Person, SettingsRose, cached.displayName ?: "Anonymous Haka account", chevron = true)
        ProtectCard(viewModel::linkGoogle)
        SettingsRow(Icons.Rounded.Group, SettingsGreen, "Connection: ${if (cached.coupleId != null) "Connected" else "Waiting for partner"}", chevron = true)
        SettingsRow(Icons.Rounded.Language, SettingsPurple, "Timezone: ${cached.timezone ?: "Asia/Kolkata"}", chevron = true)
        DividerLine()
        SectionLabel("Notifications")
        SettingsCard {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconBubble(Icons.Rounded.NotificationsNone, SettingsRose); Spacer(Modifier.width(16.dp)); Text("Partner activity", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Switch(checked = notifications, onCheckedChange = viewModel::setNotifications, colors = SwitchDefaults.colors(checkedThumbColor = Color(0xFF4D2D70), checkedTrackColor = PinkTrack))
            }
        }
        DividerLine()
        SectionLabel("Privacy")
        SettingsCard {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconBubble(Icons.Rounded.Lock, SettingsRose); Spacer(Modifier.width(16.dp)); Column(Modifier.weight(1f)) { Text("Haka is private to you and your partner.", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold); Spacer(Modifier.height(3.dp)); Text("We never share your data with anyone.", color = SettingsMuted) }; Icon(Icons.Rounded.ChevronRight, null, tint = SettingsMuted)
            }
        }
        SettingsCard(border = SettingsRose.copy(alpha = .4f), background = Color(0x332E1422)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconBubble(Icons.Rounded.Logout, SettingsRose); Spacer(Modifier.width(16.dp)); TextButton(onClick = { viewModel.signOut(onSignOut) }, contentPadding = PaddingValues(0.dp)) { Text("Sign out", color = Color(0xFFFF91AC), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold) }; Spacer(Modifier.weight(1f)); Icon(Icons.Rounded.ChevronRight, null, tint = Color(0xFFFFB1C4))
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable private fun SectionLabel(text: String) { Text(text, color = Color(0xFFFF7FA1), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }

@Composable
private fun ProtectCard(onSecure: () -> Unit) {
    BoxWithConstraints {
        val compact = maxWidth < 390.dp
        SettingsCard(border = Color(0x665C294C), background = Color(0x40271927)) {
            if (compact) {
                Column(Modifier.fillMaxWidth()) {
                    IconBubble(Icons.Rounded.Shield, SettingsRose)
                    Spacer(Modifier.height(14.dp))
                    ProtectCopy(onSecure)
                }
            } else {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                    IconBubble(Icons.Rounded.Shield, SettingsRose); Spacer(Modifier.width(18.dp))
                    ProtectCopy(onSecure, Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ProtectCopy(onSecure: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text("Protect your Haka", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Spacer(Modifier.height(8.dp))
        Text("Link Google to this signed-in account before changing phones. Your existing couple and heart stay attached to the same Supabase user.", color = SettingsMuted, style = MaterialTheme.typography.bodyLarge, lineHeight = 26.sp); Spacer(Modifier.height(16.dp))
        OutlinedButton(onClick = onSecure, shape = RoundedCornerShape(24.dp), border = androidx.compose.foundation.BorderStroke(1.5.dp, SettingsRose), contentPadding = PaddingValues(horizontal = 22.dp, vertical = 10.dp)) { Text("G", color = SettingsRose, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Spacer(Modifier.width(12.dp)); Text("Secure with Google", color = Color(0xFFFF91AC), fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun SettingsRow(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, text: String, chevron: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) { IconBubble(icon, tint); Spacer(Modifier.width(16.dp)); Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); if (chevron) Icon(Icons.Rounded.ChevronRight, null, tint = SettingsMuted, modifier = Modifier.size(30.dp)) }
}

@Composable
private fun SettingsCard(border: Color = SettingsLine, background: Color = SettingsCard, content: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(background).border(1.dp, border, RoundedCornerShape(22.dp)).padding(20.dp), content = content)
}

@Composable private fun IconBubble(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color) { Surface(Modifier.size(58.dp), shape = CircleShape, color = tint.copy(alpha = .12f)) { Box(contentAlignment = Alignment.Center) { Icon(icon, null, tint = tint, modifier = Modifier.size(29.dp)) } } }
@Composable private fun DividerLine() { Box(Modifier.fillMaxWidth().height(1.dp).background(SettingsLine)) }
