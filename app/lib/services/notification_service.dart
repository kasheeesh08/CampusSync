import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';

/// Device-scheduled reminders. Android delivers these at approximately the
/// requested time (inexact alarms, battery optimisations may delay them),
/// so the UI never promises exact delivery.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  tz.Location? _location;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _failed = false;

  /// False when the platform plugin could not start; reminders are then
  /// reported as unavailable instead of failing the calling flow.
  bool get available => supported && !_failed;

  Future<void> init(String timezone) async {
    if (!available || _ready) return;
    try {
      tzdata.initializeTimeZones();
      _location = tz.getLocation(timezone);
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
    } catch (e) {
      _failed = true;
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Returns whether notifications are permitted (Android 13+ asks the user).
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Whether Android currently lets this app show notifications (null if unknown).
  Future<bool?> enabled() async {
    if (!_ready) return null;
    return _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
  }

  static int idFor(String key) => key.hashCode & 0x7fffffff;

  /// Replaces all pending reminders with [reminders]. Rescheduling from
  /// scratch keeps the device consistent after timetable edits or
  /// cancellations and prevents duplicates.
  Future<int> replaceAll(List<PlannedReminder> reminders) async {
    if (!_ready || _location == null) return 0;
    // Cancel only pending (scheduled) reminders. cancelAll() would also remove
    // notifications already shown, e.g. a focus-completion notice that fired
    // the moment the app woke up and settled the session.
    await _plugin.cancelAllPendingNotifications();
    final now = tz.TZDateTime.now(_location!);
    var count = 0;
    final seen = <int>{};
    for (final r in reminders) {
      final when = tz.TZDateTime(_location!, r.at.year, r.at.month, r.at.day, r.at.hour, r.at.minute, r.at.second);
      if (!when.isAfter(now) || !seen.add(idFor(r.key))) continue;
      await _plugin.zonedSchedule(
        id: idFor(r.key),
        scheduledDate: when,
        title: r.title,
        body: r.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'campussync_reminders',
            'Reminders',
            channelDescription: 'Class, exam and deadline reminders',
            importance: Importance.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      count++;
    }
    return count;
  }

  Future<void> showNow(String title, String body) async {
    if (!_ready) return;
    await _plugin.show(
      id: idFor('now:$title:$body'),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('campussync_updates', 'Campus updates', importance: Importance.defaultImportance),
      ),
    );
  }

  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }
}
