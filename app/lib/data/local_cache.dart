import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'campus_data.dart';

class AppPreferences {
  final bool classReminders;
  final bool examReminders;
  final bool deadlineReminders;
  final int reminderLeadMinutes;
  final String themeMode; // light | dark | system
  final double textScale;
  final bool reduceMotion;
  final int characterColor; // cosmetic only, index into characterColors

  const AppPreferences({
    this.classReminders = false,
    this.examReminders = true,
    this.deadlineReminders = true,
    this.reminderLeadMinutes = 10,
    this.themeMode = 'light',
    this.textScale = 1.0,
    this.reduceMotion = false,
    this.characterColor = 0,
  });

  factory AppPreferences.fromJson(Map<String, dynamic> j) => AppPreferences(
    classReminders: j['classReminders'] == true,
    examReminders: j['examReminders'] != false,
    deadlineReminders: j['deadlineReminders'] != false,
    reminderLeadMinutes: (j['reminderLeadMinutes'] as num?)?.toInt() ?? 10,
    themeMode: j['themeMode'] as String? ?? 'light',
    textScale: (j['textScale'] as num?)?.toDouble() ?? 1.0,
    reduceMotion: j['reduceMotion'] == true,
    characterColor: (j['characterColor'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'classReminders': classReminders,
    'examReminders': examReminders,
    'deadlineReminders': deadlineReminders,
    'reminderLeadMinutes': reminderLeadMinutes,
    'themeMode': themeMode,
    'textScale': textScale,
    'reduceMotion': reduceMotion,
    'characterColor': characterColor,
  };

  AppPreferences copyWith({
    bool? classReminders,
    bool? examReminders,
    bool? deadlineReminders,
    int? reminderLeadMinutes,
    String? themeMode,
    double? textScale,
    bool? reduceMotion,
    int? characterColor,
  }) => AppPreferences(
    classReminders: classReminders ?? this.classReminders,
    examReminders: examReminders ?? this.examReminders,
    deadlineReminders: deadlineReminders ?? this.deadlineReminders,
    reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
    themeMode: themeMode ?? this.themeMode,
    textScale: textScale ?? this.textScale,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    characterColor: characterColor ?? this.characterColor,
  );
}

/// Device-local persistence: last-synced snapshot, saved announcements,
/// profile and preferences. Nothing here is ever sent to the server.
class LocalCache {
  static const _snapshotKey = 'cs.snapshot.v1';
  static const _snapshotAtKey = 'cs.snapshotAt.v1';
  static const _savedKey = 'cs.savedAnnouncements.v1';
  static const _profileKey = 'cs.profile.v1';
  static const _prefsKey = 'cs.prefs.v1';
  static const _demoProfileKey = 'cs.demoProfile.v1';

  final SharedPreferences _p;
  LocalCache(this._p);

  /// Shared preferences store, for other device-local repositories.
  SharedPreferences get prefs => _p;

  static Future<LocalCache> open() async => LocalCache(await SharedPreferences.getInstance());

  Future<void> saveSnapshot(CampusData data) async {
    await _p.setString(_snapshotKey, jsonEncode(data.toSeed()));
    await _p.setString(_snapshotAtKey, (data.syncedAt ?? DateTime.now()).toIso8601String());
  }

  CampusData? loadSnapshot() {
    final raw = _p.getString(_snapshotKey);
    if (raw == null) return null;
    try {
      return CampusData.fromSeed(
        jsonDecode(raw) as Map<String, dynamic>,
        origin: DataOrigin.cache,
        syncedAt: DateTime.tryParse(_p.getString(_snapshotAtKey) ?? ''),
      );
    } catch (_) {
      return null; // corrupt or old-format cache is ignored, never shown half-parsed
    }
  }

  /// Saved announcements keep a full copy so they stay readable offline.
  Map<String, Announcement> loadSaved() {
    final raw = _p.getString(_savedKey);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw) as List;
      return {for (final m in list) (m as Map)['id'] as String: Announcement.fromJson(Map<String, dynamic>.from(m))};
    } catch (_) {
      return {};
    }
  }

  Future<void> storeSaved(Map<String, Announcement> saved) =>
      _p.setString(_savedKey, jsonEncode([for (final a in saved.values) a.toJson()]));

  StudentProfile? loadProfile(String key) {
    final raw = _p.getString(key == 'demo' ? _demoProfileKey : _profileKey);
    if (raw == null) return null;
    try {
      return StudentProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> storeProfile(String key, StudentProfile? p) async {
    final k = key == 'demo' ? _demoProfileKey : _profileKey;
    p == null ? await _p.remove(k) : await _p.setString(k, jsonEncode(p.toJson()));
  }

  AppPreferences loadPrefs() {
    final raw = _p.getString(_prefsKey);
    if (raw == null) return const AppPreferences();
    try {
      return AppPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> storePrefs(AppPreferences prefs) => _p.setString(_prefsKey, jsonEncode(prefs.toJson()));

  Future<void> clearAccountData() async {
    await _p.remove(_snapshotKey);
    await _p.remove(_snapshotAtKey);
    await _p.remove(_profileKey);
    await _p.remove(_savedKey);
  }
}
