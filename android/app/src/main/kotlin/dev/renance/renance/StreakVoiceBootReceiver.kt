package dev.renance.renance

// The boot twin (2026-10-26): after a restart or an app update the
// alarm is gone with the process, so the daily 19:00 voice would die
// the first time the student reboots. This receiver re-arms it from
// the persisted payload - no Dart ever has to run first.

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StreakVoiceBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> StreakVoiceAlarm.armNext(context)
        }
    }
}
