import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/focus.dart';

/// Storage boundary for focus sessions. Today only a device-local
/// implementation exists; a Firestore implementation can be added later
/// (e.g. `students/{uid}/focusSessions`) without changing callers.
abstract class FocusRepository {
  /// Where records live, shown to the user ("Saved on this device").
  String get storageLabel;
  Future<FocusSession?> loadActive();
  Future<void> saveActive(FocusSession? session);
  Future<List<FocusSession>> history();
  Future<void> addToHistory(FocusSession session);
}

class LocalFocusRepository implements FocusRepository {
  static const _activeKey = 'cs.focus.active.v1';
  static const _historyKey = 'cs.focus.history.v1';
  static const maxHistory = 50;

  final SharedPreferences _p;
  LocalFocusRepository(this._p);

  @override
  String get storageLabel => 'Saved on this device only (not synced to the server)';

  @override
  Future<FocusSession?> loadActive() async {
    final raw = _p.getString(_activeKey);
    if (raw == null) return null;
    try {
      return FocusSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _p.remove(_activeKey); // corrupt record is discarded, never half-shown
      return null;
    }
  }

  @override
  Future<void> saveActive(FocusSession? s) async => s == null ? _p.remove(_activeKey) : _p.setString(_activeKey, jsonEncode(s.toJson()));

  @override
  Future<List<FocusSession>> history() async {
    final raw = _p.getString(_historyKey);
    if (raw == null) return [];
    try {
      return [for (final m in jsonDecode(raw) as List) FocusSession.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> addToHistory(FocusSession s) async {
    final list = [s, ...(await history()).where((x) => x.id != s.id)].take(maxHistory).toList();
    await _p.setString(_historyKey, jsonEncode([for (final x in list) x.toJson()]));
  }
}
