package dev.renance.renance

// The 19:00 alarm fire: start the voice service (banner + spoken line)
// and keep the daily chain alive by arming tomorrow. When the OS blocks
// the background service start (OEM saver without the exemption), the
// plain banner still posts - the reminder is never lost to a block.

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class StreakVoiceAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val line = intent.getStringExtra(StreakVoiceService.EXTRA_LINE)
            ?: StreakVoiceService.DEFAULT_LINE
        val pitch = intent.getFloatExtra(StreakVoiceService.EXTRA_PITCH, 1.0f)
        val title = intent.getStringExtra(StreakVoiceService.EXTRA_TITLE)
            ?: StreakVoiceService.DEFAULT_TITLE

        try {
            val service = StreakVoiceService.intent(context, line, pitch, title)
            // startForegroundService is API 26+; 24-25 ride plain
            // startService (pre-O has no background-start restriction
            // for a broadcast receiver's own process).
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        } catch (_: Exception) {
            // The FGS start is blocked: the banner alone still lands.
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager
                nm.notify(2003, StreakBanner.build(context, title, line))
            } catch (_: Exception) {}
        }

        // The self-perpetuating chain: tomorrow, same hour, same voice.
        StreakVoiceAlarm.armNext(context)
    }
}
