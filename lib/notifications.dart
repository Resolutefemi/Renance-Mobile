/// Device notifications (founder directive 2026-10-04): the app used to
/// request the notification permission but never post anything, so
/// nothing ever "dropped" on the phone. This service wraps
/// flutter_local_notifications - review-due nudges and download
/// completions land as real Android notifications on the 'renance'
/// channel. Everything is best-effort: a notification failure never
/// blocks study, and every call is safe before init or without the
/// permission (it just no-ops).
///
/// Founder pass VIII (the Duolingo streak): the service also schedules
/// a DAILY streak reminder (id 2003) at the student's local 19:00,
/// rotating through the founder's ten voice lines - and, when tapped
/// from the background, SPEAKS the day's line through on-device TTS
/// with a rotating voice. Every new path stays best-effort like the
/// old ones: a failed schedule or a missing TTS service never throws.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class RenanceNotifications {
  RenanceNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// The native streak-voice alarm (founder 2026-10-26, the real fix
  /// for "the notification only talks when I open the app"): the plugin
  /// fires a NATIVE alarm receiver that can only post a banner - no
  /// Dart runs, so the TTS voice never played unattended. The
  /// 'renance/voice' channel arms a SECOND, native alarm chain
  /// (StreakVoiceAlarm -> StreakVoiceAlarmReceiver ->
  /// StreakVoiceService) that posts the banner AND speaks the day's
  /// line through Android's TextToSpeech with the app closed. The
  /// plugin's schedule below stays as the visual belt-over-braces:
  /// both fires carry the same id 2003 and the same text, so the tray
  /// shows ONE banner, and only the native chain talks.
  static const MethodChannel _voiceChannel = MethodChannel('renance/voice');

  /// Call once at app start. Android-only (the shell ships Android
  /// builds; other platforms no-op).
  static Future<void> init() async {
    if (_ready || !Platform.isAndroid) return;
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);
    try {
      // The background entry point (founder pass VIII): a tap on the
      // scheduled streak reminder wakes the voice inside a background
      // isolate, so the handler must be a TOP-LEVEL function (see the
      // file tail) - a closure would break the plugin's callback handle.
      await _plugin.initialize(
        settings,
        onDidReceiveBackgroundNotificationResponse: _backgroundHandler,
      );
      _ready = true;
    } catch (_) {
      // Notifications are sugar, never a gate.
    }
    // Best-effort timezone database so the daily streak reminder can be
    // zoned (zonedSchedule cannot run without a location). The OS zone
    // name plugin (flutter_timezone) drags a Java+Kotlin Android module
    // whose JVM pins break the release Gradle graph, so Renance pins to
    // Africa/Lagos - home crowd, UTC+1, no DST; WAT is the local time
    // that matters for a Nigerian exam-prep nudge.
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Lagos'));
    } catch (_) {
      // Scheduling stays silent this session; nothing else is hurt.
    }
  }

  /// prefs key recording that the one-time ALARM PRECISION ask (the
  /// exact-alarm special access + the battery-optimization exemption)
  /// has been ACCEPTED - once granted, the ask never repeats.
  static const String alarmAskKey = 'renance.alarmPrecisionAsked';

  /// prefs key counting how many times the alarm-precision ask was
  /// dismissed with "Not now" (2026-10-26 fix: the ask used to mark
  /// itself done BEFORE the dialog, so one "Not now" quietly retired
  /// the exact-alarm grant forever and the reminder stayed inexact -
  /// exactly the "only fires when the app is open" class of bug).
  /// Dismissals retry up to [_alarmAskMaxAttempts] opens.
  static const String alarmAskAttemptsKey = 'renance.alarmPrecisionAttempts';
  static const int _alarmAskMaxAttempts = 3;

  /// The alarm-precision pass (2026-10-26, the "reminder only fires
  /// when the app is open" bug): asks Android for the two grants an
  /// unattended alarm needs, best-effort and safe to repeat -
  ///
  ///  1. SCHEDULE_EXACT_ALARM (Alarms & reminders special access,
  ///     Android 12+): exact alarms survive Doze batch-deferral; the
  ///     inexact fallback the old schedule rode could slip hours or
  ///     never land under OEM battery savers.
  ///  2. REQUEST_IGNORE_BATTERY_OPTIMIZATIONS: the direct system
  ///     dialog; Xiaomi/OPPO/Huawei kill uncleared apps hard enough
  ///     to cancel AlarmManager jobs entirely.
  ///
  /// Never throws, never blocks study: a denied grant simply leaves
  /// the reminder on the (still scheduled) inexact path.
  static Future<void> ensureAlarmPrecision() async {
    if (!Platform.isAndroid) return;
    try {
      if (await Permission.scheduleExactAlarm.isGranted != true) {
        await Permission.scheduleExactAlarm.request();
      }
    } catch (_) {
      // Pre-12 devices answer denied; the inexact schedule covers them.
    }
    try {
      if (await Permission.ignoreBatteryOptimizations.isGranted != true) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // The exemption is sugar; the OS dialog failing is not fatal.
    }
  }

  /// Whether the one-time alarm-precision ask already ran (prefs).
  static Future<bool> alarmPrecisionAsked() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(alarmAskKey) ?? false;
    } catch (_) {
      return true; // prefs trouble: skip the ask rather than nag forever.
    }
  }

  /// Marks the alarm-precision ask as done (the nag flow calls this
  /// when the student taps "Allow precise reminders" - NOT before the
  /// dialog: a dismissed ask must come back next launch).
  static Future<void> markAlarmPrecisionAsked() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(alarmAskKey, true);
    } catch (_) {
      // Sugar, never a gate.
    }
  }

  /// Whether the dismiss-retry budget still allows another ask (a
  /// "Not now" counts one attempt; after three the ask retires and
  /// the reminder stays on the inexact fallback).
  static Future<bool> alarmPrecisionCanAsk() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return (prefs.getInt(alarmAskAttemptsKey) ?? 0) < _alarmAskMaxAttempts;
    } catch (_) {
      return false; // prefs trouble: stop nagging rather than nag forever.
    }
  }

  /// Records one "Not now" dismissal of the alarm-precision ask.
  static Future<void> markAlarmPrecisionDismissed() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int attempts = (prefs.getInt(alarmAskAttemptsKey) ?? 0) + 1;
      await prefs.setInt(alarmAskAttemptsKey, attempts);
    } catch (_) {
      // Sugar, never a gate.
    }
  }

  /// Asks for the runtime permission (Android 13+); returns whether
  /// notifications may be shown. Safe to call repeatedly.
  static Future<bool> ensurePermission() async {
    await init();
    if (!_ready) return false;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    try {
      final bool? granted = await android.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether notifications are already enabled (Android only; any
  /// failure or other platform answers false so callers keep asking).
  static Future<bool> isPermissionGranted() async {
    await init();
    if (!_ready) return false;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    try {
      return await android.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Posts one immediate notification. Silently ignored before init or
  /// without the permission.
  static Future<void> show(int id, String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(id, title, body, _details);
    } catch (_) {
      // Never crash study over a notification.
    }
  }

  /// Re-arms the DAILY streak reminder (founder pass VIII): cancelled
  /// first so a re-call never stacks copies, then scheduled for the
  /// next occurrence of the local [hour]:00 and repeated daily
  /// (matchDateTimeComponents: time). The body is the day's rotating
  /// voice line, so the popup and the spoken line always agree.
  ///
  /// Respects the Settings 'Study Reminders' toggle ('renance.reminders'):
  /// an explicit false cancels instead of scheduling - the key ABSENT
  /// means ON (the founder's one-nudge-a-day promise is the default).
  static Future<void> scheduleDailyStreakReminder({int hour = 19}) async {
    await init();
    if (!_ready) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(remindersKey) &&
          !(prefs.getBool(remindersKey) ?? true)) {
        await _plugin.cancel(streakReminderId);
        return;
      }
      await _plugin.cancel(streakReminderId);
      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduled =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
      if (!scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      // EXACT first (2026-10-26): an exact allow-while-idle alarm fires
      // at 19:00 through Doze and OEM idle - the inexact mode the old
      // schedule rode gets batched out and, on MIUI-class devices, is
      // the core reason the reminder only ever landed on app open.
      // exactAllowWhileIdle throws SecurityException when the user has
      // not granted the special access; fall back to the inexact
      // schedule (still allow-while-idle) so the reminder is never
      // lost, just potentially deferred.
      try {
        await _plugin.zonedSchedule(
          streakReminderId,
          streakReminderTitle,
          _todayVoiceLine().$1,
          scheduled,
          _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (_) {
        await _plugin.zonedSchedule(
          streakReminderId,
          streakReminderTitle,
          _todayVoiceLine().$1,
          scheduled,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
      // The VOICE half (the part the plugin can never do): arm the
      // native alarm with today's line + pitch, so StreakVoiceService
      // posts the banner and speaks it with the app closed. Best-effort
      // like everything here - an older host or a missing channel
      // leaves the (still scheduled) plugin reminder on the tray.
      try {
        final (String line, String gender) = _todayVoiceLine();
        await _voiceChannel.invokeMethod<void>(
          'schedule',
          <String, dynamic>{
            'hour': hour,
            'line': line,
            'pitch': _pitchFor(gender),
            'title': streakReminderTitle,
          },
        );
      } catch (_) {
        // No native receiver (pre-update process): the plugin banner
        // still shows; the voice waits for the next app open.
      }
    } catch (_) {
      // Scheduling is sugar, never a gate.
    }
  }

  /// Speaks today's streak line through on-device TTS, once per day
  /// (deduped in prefs so a background tap and an app open can never
  /// double-speak). The pitch is the gender guarantee; the voice pick
  /// is best-effort sugar over getVoices/setVoice. Everything is
  /// guarded - a device without a TTS service just stays silent.
  static Future<void> speakStreakReminder() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String dedupKey = _voiceDedupKey();
      if (prefs.getBool(dedupKey) ?? false) return;
      await prefs.setBool(dedupKey, true);
      final (String line, String gender) = _todayVoiceLine();
      final FlutterTts tts = FlutterTts();
      try {
        await tts.setLanguage('en-US');
        // The pitch carries the founder's voice rotation (woman 1.0,
        // girl 1.35, man 0.72) - the guarantee even when the voice pick
        // below finds nothing.
        await tts.setPitch(_pitchFor(gender));
        try {
          // `getVoices` is a getter in some flutter_tts majors and a
          // method in others - awaiting the bare reference compiles for
          // both and degrades to the pitch-only roll when it yields a
          // function object instead of a voice list.
          final dynamic voices = await tts.getVoices;
          if (voices is List) {
            final bool wantFemale = gender != 'man';
            for (final dynamic v in voices) {
              if (v is! Map) continue;
              final String name = (v['name'] ?? '').toString();
              final String locale = (v['locale'] ?? '').toString();
              final String lower = name.toLowerCase();
              // 'female' contains 'male', so the male match must
              // explicitly exclude the female names.
              final bool female = lower.contains('female');
              final bool male = lower.contains('male') && !female;
              if (locale.toLowerCase().startsWith('en') &&
                  (wantFemale ? female : male)) {
                await tts.setVoice(<String, String>{
                  'name': name,
                  'locale': locale,
                });
                break;
              }
            }
          }
        } catch (_) {
          // Voice pick failed - the pitch above still carries the roll.
        }
        await tts.speak(line);
      } catch (_) {
        // No TTS service here - the notification itself still showed.
      }
    } catch (_) {
      // Voice is sugar, never a gate.
    }
  }

  /// The nag entry (founder pass VIII): re-arms tonight's reminder, and
  /// once it is past 19:00 local with the day's line still unsaid, the
  /// reminder drops immediately - the student opened the app anyway, so
  /// the nudge lands and the voice plays right now.
  static Future<void> dailyStreakTouch() async {
    await scheduleDailyStreakReminder();
    try {
      if (DateTime.now().hour < 19) return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_voiceDedupKey()) ?? false) return;
      await show(streakReminderId, streakReminderTitle, _todayVoiceLine().$1);
      await speakStreakReminder();
    } catch (_) {
      // Sugar, never a gate.
    }
  }

  /// prefs dedup key for the day's spoken line ('yyyy-MM-dd', padded).
  static String _voiceDedupKey() {
    final DateTime now = DateTime.now();
    final String mm = now.month.toString().padLeft(2, '0');
    final String dd = now.day.toString().padLeft(2, '0');
    return 'renance.streakVoice.${now.year}-$mm-$dd';
  }

  /// The day's (line, gender) from the founder rotation: day 0 is
  /// 2026-01-01, the line marches through the ten founder lines and the
  /// gender through woman/girl/man on the same tick.
  static (String, String) _todayVoiceLine() {
    final int dayIndex = DateTime.now().difference(DateTime(2026, 1, 1)).inDays;
    return (
      streakVoiceLines[dayIndex % streakVoiceLines.length],
      const <String>['woman', 'girl', 'man'][dayIndex % 3],
    );
  }

  /// The gender's pitch (the founder's voice rotation): woman 1.0,
  /// girl 1.35, man 0.72. Shared by the on-open TTS speaker and the
  /// native voice alarm (which cannot compute Dart-side constants).
  static double _pitchFor(String gender) => switch (gender) {
        'girl' => 1.35,
        'man' => 0.72,
        _ => 1.0,
      };

  /// The Settings 'Study Reminders' switch calls this on OFF: tonight's
  /// zoned reminder is dropped immediately - and so is the native
  /// voice alarm. ON goes through [scheduleDailyStreakReminder] which
  /// re-arms both.
  static Future<void> cancelDailyStreakReminder() async {
    await init();
    try {
      await _voiceChannel.invokeMethod<void>('cancel');
    } catch (_) {
      // Sugar, never a gate.
    }
    if (!_ready) return;
    try {
      await _plugin.cancel(streakReminderId);
    } catch (_) {
      // Sugar, never a gate.
    }
  }

  /// The one channel every Renance notification rides. v2 (2026-10-26):
  /// channel settings are immutable once created, and the original
  /// 'renance' channel shipped at DEFAULT importance - on MIUI-class
  /// devices that files the reminder into the silent drawer. The v2
  /// channel is HIGH: heads-up banner + sound, which is what a daily
  /// streak nudge (the app's whole one-nudge-a-day promise) needs.
  static const AndroidNotificationDetails _channel = AndroidNotificationDetails(
    'renance_v2',
    'Renance updates',
    channelDescription: 'Study reminders and download progress',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const NotificationDetails _details = NotificationDetails(
    android: _channel,
  );

  /// Stable ids so a second notification replaces (not stacks with) the
  /// same kind.
  static const int downloadDoneId = 2001;
  static const int reviewDueId = 2002;
  static const int streakReminderId = 2003;

  /// prefs key of the Settings 'Study Reminders' switch. ABSENT = ON.
  static const String remindersKey = 'renance.reminders';

  /// Tonight's reminder headline (founder pass VIII).
  static const String streakReminderTitle = 'Don\'t break your streak! 🔥';

  /// The founder's ten reminder lines, spoken and shown in this exact
  /// rotation (one per day, day 0 = 2026-01-01).
  static const List<String> streakVoiceLines = <String>[
    'Your streak is on the line! Jump back into Renance and finish today\'s session.',
    'Don\'t break the chain. One quick session on Renance keeps your streak alive.',
    'Only a few hours left to protect your streak! Open Renance now.',
    'Time to level up. Hop into Renance and crush today\'s goals!',
    'Consistency builds mastery. Open Renance and wrap up your lesson for today.',
    'Your daily progress is waiting. Let\'s get today\'s practice done!',
    'Renance reminder: complete today\'s coursework to keep your streak!',
    'Hey, don\'t lose your streak! Time for your daily Renance review.',
    'One lesson is all it takes - keep your Renance streak burning!',
    'Champions show up daily. Your streak is waiting on Renance!',
  ];
}

/// Background-isolate entry (founder pass VIII): tapping tonight's
/// streak reminder speaks the day's line. The plugin resolves this
/// through a callback handle, so it MUST stay a top-level function
/// carrying the vm:entry-point pragma - moving it into the class kills
/// the handle and the background tap goes quiet.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(NotificationResponse response) async {
  try {
    await RenanceNotifications.speakStreakReminder();
  } catch (_) {}
}
