package dev.renance.renance

// StreakVoiceService (founder 2026-10-26, "the notification only talks
// when I open the app"): the missing half of the daily 19:00 reminder.
// Until today the scheduled streak reminder could only SHOW a banner -
// flutter_local_notifications' alarm receiver posts the notification
// natively, no Dart runs, so the on-device TTS voice only ever played
// when the founder tapped the banner or opened the app. This foreground
// service closes the gap: the alarm receiver starts it, it posts the
// reminder banner itself (channel 'renance_v2', the same id 2003 the
// plugin uses - one tray entry, never two), SPEAKS the day's line
// through Android's native TextToSpeech with the same gendered pitch
// Dart picked, marks the day's spoken-line dedup key in the Flutter
// prefs (so an app-open touch never double-speaks), and stops.
//
// shortService (Android 14+): a self-terminating foreground service
// started from an exact alarm - the one legal background start for a
// ~20 second speak. Pre-34 devices ride a plain foreground service.
// Every path is defensive: a missing TTS engine or a blocked start
// degrades to the plain notification, never a crash.

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

class StreakVoiceService : Service() {

    private var tts: TextToSpeech? = null
    private val watchdog = Handler(Looper.getMainLooper())
    private var finished = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val line = intent?.getStringExtra(EXTRA_LINE) ?: DEFAULT_LINE
        val pitch = intent?.getFloatExtra(EXTRA_PITCH, 1.0f) ?: 1.0f
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE

        try {
            startInForeground(title, line)
        } catch (e: Exception) {
            // A blocked FGS start (OEM saver, missing grant) still owes
            // the student the banner - post it plainly and stop.
            try { postPlain(title, line) } catch (_: Exception) {}
            stopSelf()
            return START_NOT_STICKY
        }

        // The day's dedup key, written exactly like Dart's
        // renance.streakVoice.<yyyy-MM-dd> - shared_preferences stores
        // its booleans under the 'flutter.' prefix in the
        // 'FlutterSharedPreferences' file, so an app-open touch after
        // the scheduled voice finds the day already said.
        try {
            val cal = java.util.Calendar.getInstance()
            val day = String.format(
                "%04d-%02d-%02d",
                cal.get(java.util.Calendar.YEAR),
                cal.get(java.util.Calendar.MONTH) + 1,
                cal.get(java.util.Calendar.DAY_OF_MONTH),
            )
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("flutter.renance.streakVoice.$day", true)
                .apply()
        } catch (_: Exception) {}

        // The voice. Everything below is best-effort: a device without
        // a TTS service still got its banner (startInForeground above).
        try {
            tts = TextToSpeech(applicationContext) { status ->
                if (finished) return@TextToSpeech
                if (status != TextToSpeech.SUCCESS) {
                    finish()
                    return@TextToSpeech
                }
                try {
                    val engine = tts ?: return@TextToSpeech
                    engine.language = Locale.US
                    engine.setPitch(pitch)
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) { finish() }
                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) { finish() }
                    })
                    val params = android.os.Bundle()
                    params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, UTTERANCE_ID)
                    engine.speak(line, TextToSpeech.QUEUE_FLUSH, params, UTTERANCE_ID)
                } catch (_: Exception) {
                    finish()
                }
            }
        } catch (_: Exception) {
            finish()
        }
        // The hard stop: no TTS callback (engine wedged, service muted)
        // may never pin a foreground slot - shortService caps us at ~3
        // minutes anyway, but we are done long before that.
        watchdog.postDelayed({ finish() }, WATCHDOG_MS)
        return START_NOT_STICKY
    }

    private fun startInForeground(title: String, line: String) {
        val notification = StreakBanner.build(this, title, line)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(StreakBanner.NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
        } else {
            @Suppress("DEPRECATION")
            startForeground(StreakBanner.NOTIFICATION_ID, notification)
        }
    }

    private fun postPlain(title: String, line: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(StreakBanner.NOTIFICATION_ID, StreakBanner.build(this, title, line))
    }

    private fun finish() {
        if (finished) return
        finished = true
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        try {
            // DETACH keeps the reminder banner in the tray after the
            // service stops - only the VOICE ends here, not the nudge.
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(Service.STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(false)
            }
        } catch (_: Exception) {}
        stopSelf()
    }

    override fun onDestroy() {
        watchdog.removeCallbacksAndMessages(null)
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    companion object {
        const val CHANNEL_ID = "renance_v2"
        const val NOTIFICATION_ID = 2003
        const val EXTRA_LINE = "line"
        const val EXTRA_PITCH = "pitch"
        const val EXTRA_TITLE = "title"
        const val UTTERANCE_ID = "renance.streak.voice"
        const val DEFAULT_LINE = "Your streak is waiting on Renance!"
        const val DEFAULT_TITLE = "Don't break your streak! \uD83D\uDD25"
        const val WATCHDOG_MS = 25_000L

        fun intent(context: Context, line: String, pitch: Float, title: String): Intent =
            Intent(context, StreakVoiceService::class.java)
                .putExtra(EXTRA_LINE, line)
                .putExtra(EXTRA_PITCH, pitch)
                .putExtra(EXTRA_TITLE, title)
    }
}
