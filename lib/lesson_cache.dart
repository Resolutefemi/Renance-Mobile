/// The local lesson cache (founder 2026-10-26, the R2-link pass).
///
/// When the API serves a lesson document that the Cloudflare R2 bucket
/// backs (the doc carries a `blobUrl`), the shell also banks the raw
/// JSON locally. A lesson the cloud has served once therefore always
/// opens again - instantly, and offline: when the API is cold (Render
/// free tier) or the generator is still writing, the overlay replays
/// the cached copy instead of staring at a loader.
///
/// Everything here is sugar by the house doctrine: a failed cache
/// write or read never blocks study - the API path stays the truth.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LessonCache {
  LessonCache._();

  static const String _indexKey = 'renance.lessonCache';
  static const int _cap = 64; // ~16 full lessons, oldest evicted first.

  static String _docKey(String topicId) => 'renance.lessonDoc.$topicId';

  /// Banks one raw content-response payload. Only complete documents
  /// (real notes AND a real quiz) are worth disk space - the loader
  /// can always re-poll for the rest.
  static Future<void> put(String topicId, Map<String, dynamic> doc) async {
    try {
      final dynamic notes = doc['notes'];
      final dynamic quiz = doc['quiz'];
      if (notes is! List || notes.isEmpty) return;
      if (quiz is! List || quiz.isEmpty) return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_docKey(topicId), jsonEncode(doc));
      final List<String> ids = prefs.getStringList(_indexKey) ?? <String>[];
      ids.remove(topicId);
      ids.add(topicId);
      while (ids.length > _cap) {
        final String evict = ids.removeAt(0);
        await prefs.remove(_docKey(evict));
      }
      await prefs.setStringList(_indexKey, ids);
    } catch (_) {
      // Cache trouble is invisible; the API path still serves.
    }
  }

  /// Reads one cached raw payload, or null. A torn entry is dropped.
  static Future<Map<String, dynamic>?> get(String topicId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_docKey(topicId));
      if (raw == null || raw.isEmpty) return null;
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}
