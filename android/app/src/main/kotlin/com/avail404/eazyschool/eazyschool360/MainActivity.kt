package com.avail404.eazyschool.eazyschool360

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
            "eazyschool_default",
            "School notifications",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Announcements, homework, results, leave and messages"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
