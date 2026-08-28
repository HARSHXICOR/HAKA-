package com.haka.app.feature.pairing

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@Composable fun PairingScreen(onPaired: () -> Unit, viewModel: PairingViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState(); var create by rememberSaveable { mutableStateOf(true) }; var name by rememberSaveable { mutableStateOf("") }; var code by rememberSaveable { mutableStateOf("") }
    val clipboard = LocalClipboardManager.current; val context = LocalContext.current
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Spacer(Modifier.height(36.dp)); Text("Haka", style = MaterialTheme.typography.displaySmall); Text(if (create) "Create your Haka" else "Join your Haka", style = MaterialTheme.typography.headlineSmall)
        if (state.inviteCode != null) {
            Text("Invite your partner", style = MaterialTheme.typography.titleLarge); Text(state.inviteCode!!, style = MaterialTheme.typography.displayMedium)
            Button(onClick = { clipboard.setText(AnnotatedString(state.inviteCode!!)) }) { Text("Copy code") }
            OutlinedButton(onClick = { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "Join my Haka with code ${state.inviteCode}") }, "Share Haka code")) }) { Text("Share code") }
            Text("Waiting for your partner. This code expires in 15 minutes.")
        } else {
            if (create) OutlinedTextField(name, { name = it }, label = { Text("Your name (optional)") }, singleLine = true)
            else OutlinedTextField(code, { code = it.uppercase().filter(Char::isLetterOrDigit).take(8).chunked(4).joinToString("-") }, label = { Text("Invite code") }, singleLine = true)
            Button(enabled = !state.loading, onClick = { if (create) viewModel.create(name, onPaired) else viewModel.redeem(code, onPaired) }) { if (state.loading) CircularProgressIndicator(Modifier.size(20.dp)) else Text(if (create) "Create invite" else "Join Haka") }
            TextButton(onClick = { create = !create; state.error?.let { } }) { Text(if (create) "I have an invite code" else "Create a new Haka") }
        }
        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}
