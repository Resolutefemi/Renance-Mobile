package dev.renance.renance

// StreakVoiceAlarm (founder 2026-10-26, "the notification only talks
// when I open the app"): the native twin of Dart's
// scheduleDailyStreakReminder. Dart re-arms this alarm on every app
// open through the 'renance/voice' MethodChannel (MainActivity); the
// receiver self-reschedules after every fire and the boot receiver
// re-arms after a restart or an app update, so the daily 19:00 voice
// keeps its chain even when the app stays closed for days.
//
// Exact alarms (setExactAndAllowWhileIdle) survive Doze and OEM idle -
// the exact mode the reminder's fix demanded. Without the user's
// SCHEDULE_EXACT_ALARM grant the schedule falls back to
// setAndAllowWhileIdle (still idle-proof, potentially batched), which
// is the same graceful ladder Dart's zonedSchedule rides.

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

object StreakVoiceAlarm {

    private const val PREFS = "renance_voice"
    private const val KEY_HOUR = "hour"
    private const val KEY_LINE = "line"
    private const val KEY_PITCH = "pitch"
    private const val KEY_TITLE = "title"
    private const val REQUEST_CODE = 20031

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, StreakVoiceAlarmReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }

    /// Arms the next daily fire at [hour]:00 local time with the day's
    /// voice line + pitch (Dart computes both from the founder's
    /// rotation). The payload is persisted so the boot receiver can
    /// re-arm without Dart ever running.
    @JvmStatic
    fun schedule(context: Context, hour: Int, line: String, pitch: Float, title: String) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putInt(KEY_HOUR, hour)
                .putString(KEY_LINE, line)
                .putFloat(KEY_PITCH, pitch)
                .putString(KEY_TITLE, title)
                .apply()
            armNext(context)
        } catch (_: Exception) {
            // Scheduling is sugar, never a gate.
        }
    }

    /// Drops the alarm (the Settings 'Study Reminders' switch on OFF).
    @JvmStatic
    fun cancel(context: Context) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pendingIntent(context))
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().clear().apply()
        } catch (_: Exception) {}
    }

    /// Re-arms from the persisted payload (boot receiver, the receiver's
    /// self-perpetuating chain). No-op when Dart never armed one.
    @JvmStatic
    fun armNext(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.contains(KEY_HOUR)) return
            val hour = prefs.getInt(KEY_HOUR, 19)
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }

            val pi = pendingIntent(context)
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                // No special access: the idle-proof inexact ladder, the
                // same trade Dart's zonedSchedule fallback makes.
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
            } else {
                try {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
                } catch (_: SecurityException) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
                }
            }
        } catch (_: Exception) {
            // Scheduling is sugar, never a gate.
        }
    }
}
