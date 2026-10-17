package com.avail404.eazyschool.eazyschool360

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // Push notifications that arrive while the app is closed are posted by
    // the system into this channel. It must exist, with high importance, for
    // them to appear as heads-up alerts and on the lock screen.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "eazyschool_general",
            "General notifications",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Announcements, homework, results, leave and messages"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            // The system default notification sound. A user's own choice in
            // the channel's settings always overrides this afterwards.
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
