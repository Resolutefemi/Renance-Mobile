package dev.renance.renance

// StreakBanner - the one reminder banner builder shared by the voice
// service and the alarm receiver's blocked-start fallback. The channel
// ('renance_v2', HIGH) matches flutter_local_notifications' channel
// declaration exactly, so the plugin's copies and ours merge into one
// tray identity; notification id 2003 is shared too, so a native fire
// and a plugin fire REPLACE each other instead of stacking.

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object StreakBanner {
    const val CHANNEL_ID = "renance_v2"
    const val NOTIFICATION_ID = 2003

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Renance updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Study reminders and download progress"
            enableVibration(true)
        }
        nm.createNotificationChannel(channel)
    }

    fun build(context: Context, title: String, line: String): Notification {
        ensureChannel(context)
        // Tapping the banner opens the app (the plugin's own scheduled
        // copy behaves the same way).
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(line)
            .setStyle(Notification.BigTextStyle().bigText(line))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
    }
}
