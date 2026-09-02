package com.haka.app.feature.navigation

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.haka.app.feature.home.HomeScreen
import com.haka.app.feature.auth.AuthScreen
import com.haka.app.feature.pairing.PairingScreen
import com.haka.app.feature.settings.SettingsScreen
import com.haka.app.feature.insights.InsightsScreen
import com.haka.app.feature.love.LoveScreen
import com.haka.app.feature.story.StoryScreen

@Composable fun HakaRoot(viewModel: SessionViewModel = hiltViewModel()) {
    val state by viewModel.session.collectAsState()
    when (val current = state) {
        SessionState.Loading -> LoadingScreen()
        SessionState.AuthRequired -> AuthScreen(viewModel::continueWithGoogle, viewModel::continueAnonymously)
        is SessionState.Failed -> if (current.cached?.coupleId != null) CoupleShell(current.cached, offline = true, onSignOut = viewModel::refresh) else PairingScreen(onPaired = viewModel::onPairingFinished)
        is SessionState.Unpaired -> PairingScreen(onPaired = viewModel::onPairingFinished)
        is SessionState.Paired -> CoupleShell(current.cached, onSignOut = viewModel::refresh)
    }
}

@Composable private fun LoadingScreen() = Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) { Text("Haka", style = MaterialTheme.typography.displaySmall); Spacer(Modifier.height(16.dp)); CircularProgressIndicator() }
}

@Composable private fun CoupleShell(cached: com.haka.app.core.model.CachedHakaState, offline: Boolean = false, onSignOut: () -> Unit) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0),
        bottomBar = { HakaBottomBar(tab) { tab = it } },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                0 -> HomeScreen(cached, offline)
                1 -> InsightsScreen(cached)
                2 -> LoveScreen(cached)
                3 -> StoryScreen(cached)
                else -> SettingsScreen(cached, onSignOut)
            }
        }
    }
}

@Composable
private fun HakaBottomBar(selected: Int, onSelected: (Int) -> Unit) {
    val items = listOf(
        Triple("Heart", Icons.Rounded.Favorite, Color(0xFFFF5C83)),
        Triple("Insights", Icons.Rounded.BarChart, Color(0xFFC9BEC7)),
        Triple("Love", Icons.Rounded.FavoriteBorder, Color(0xFFC9BEC7)),
        Triple("Us", Icons.Rounded.Favorite, Color(0xFFC9BEC7)),
        Triple("Settings", Icons.Rounded.Settings, Color(0xFFC9BEC7)),
    )
    Box(
        Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp, vertical = 8.dp)
            .height(88.dp),
    ) {
        Row(Modifier.fillMaxSize().padding(horizontal = 7.dp), verticalAlignment = Alignment.CenterVertically) {
            items.forEachIndexed { index, item ->
                val active = selected == index
                Column(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable { onSelected(index) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(item.second, null, tint = if (active) item.third else Color(0xFFC7B5C8), modifier = Modifier.size(29.dp))
                    Spacer(Modifier.height(5.dp))
                    Text(item.first, color = if (active) item.third else Color(0xFFC7B5C8), style = MaterialTheme.typography.labelLarge, maxLines = 1)
                }
            }
        }
    }
}
