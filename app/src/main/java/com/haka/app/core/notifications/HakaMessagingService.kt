package com.haka.app.core.notifications

import android.Manifest
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.haka.app.R
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.haka.app.data.heart.HakaRepository
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Registers FCM tokens and surfaces partner activity in the notification panel. */
class HakaMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        val repository = EntryPointAccessors.fromApplication(applicationContext, MessagingEntryPoint::class.java).repository()
        val deviceId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
        CoroutineScope(Dispatchers.IO).launch { runCatching { repository.registerDevice(deviceId, token, true) } }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val repository = EntryPointAccessors.fromApplication(applicationContext, MessagingEntryPoint::class.java).repository()
        when (message.data["type"]) {
            "partner_tap" -> {
                CoroutineScope(Dispatchers.IO).launch { runCatching { repository.bootstrap() } }
                showPartnerNotification(
                    title = "Shared Heart",
                    body = "Your partner added to your heart.",
                    notificationKey = "partner_tap",
                )
            }
            "thinking_of_you" -> {
                CoroutineScope(Dispatchers.IO).launch { runCatching { repository.recordThinkingPulse() } }
                showPartnerNotification(
                    title = "Thinking of You 💕",
                    body = "Your partner is thinking of you.",
                    notificationKey = message.data["eventId"] ?: "thinking_of_you",
                )
            }
            "love_note" -> {
                showPartnerNotification(
                    title = "Love Note 💌",
                    body = "Your partner sent you a private note.",
                    notificationKey = message.data["noteId"] ?: "love_note",
                )
            }
        }
    }

    private fun showPartnerNotification(title: String, body: String, notificationKey: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                100,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = NotificationCompat.Builder(this, getString(R.string.default_notification_channel_id))
            .setSmallIcon(R.drawable.ic_notification_heart)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .apply { pendingIntent?.let(::setContentIntent) }
            .build()

        NotificationManagerCompat.from(this).notify(notificationKey.hashCode(), notification)
    }
}
