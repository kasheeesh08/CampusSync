import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/focus_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/domain/focus.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final t0 = DateTime(2026, 10, 21, 9, 0);
DateTime at(int minutes, [int seconds = 0]) => t0.add(Duration(minutes: minutes, seconds: seconds));
final desk = libraryStudySpace.spots[3];

FocusSession start([int minutes = 25]) => FocusSession.start(spaceId: libraryStudySpace.id, spotId: desk.id, minutes: minutes, now: t0);

Map<String, dynamic> seed() => {
  for (final f in Directory('assets/seed').listSync().whereType<File>())
    f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
};

void main() {
  group('Focus session timing (wall-clock based)', () {
    test('remaining time counts down from the planned duration', () {
      final s = start();
      expect(s.remainingAt(t0), const Duration(minutes: 25));
      expect(s.remainingAt(at(10)), const Duration(minutes: 15));
      expect(s.completesAt, at(25));
    });

    test('pause freezes the countdown; resume shifts the completion time', () {
      final paused = start().pause(at(10));
      expect(paused.status, FocusStatus.paused);
      expect(paused.remainingAt(at(40)), const Duration(minutes: 15), reason: 'no time passes while paused');
      expect(paused.completesAt, isNull, reason: 'paused sessions have no fixed end');
      final resumed = paused.resume(at(40));
      expect(resumed.status, FocusStatus.running);
      expect(resumed.remainingAt(at(45)), const Duration(minutes: 10));
      expect(resumed.completesAt, at(55));
    });

    test('a session that ended while the app was closed completes at its exact due time', () {
      final s = start().settle(at(300)); // reopened hours later
      expect(s.status, FocusStatus.completed);
      expect(s.finishedAt, at(25));
      expect(s.focusedAt(at(300)), const Duration(minutes: 25));
    });

    test('ending early records only the focused time', () {
      final s = start().pause(at(5)).resume(at(8)).end(at(12, 30));
      expect(s.status, FocusStatus.ended);
      expect(s.focusedAt(at(99)), const Duration(minutes: 9, seconds: 30));
    });

    test('ending while paused records time up to the pause', () {
      final s = start().pause(at(7)).end(at(20));
      expect(s.focusedAt(at(20)), const Duration(minutes: 7));
    });

    test('pause/end after completion settles instead of extending', () {
      final s = start().pause(at(30));
      expect(s.status, FocusStatus.completed);
      expect(s.finishedAt, at(25));
    });

    test('duration validation rejects out-of-range values', () {
      expect(FocusSession.validateMinutes(25), isNull);
      expect(FocusSession.validateMinutes(4), contains('5–180'));
      expect(FocusSession.validateMinutes(181), contains('5–180'));
      expect(FocusSession.validateMinutes(null), isNotNull);
      expect(() => start(0), throwsArgumentError);
    });

    test('JSON round trip preserves pause state', () {
      final s = start().pause(at(3)).resume(at(6)).pause(at(10));
      final r = FocusSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(r.status, FocusStatus.paused);
      expect(r.pausedTotal, const Duration(minutes: 3));
      expect(r.remainingAt(at(50)), s.remainingAt(at(50)));
    });

    test('study spots are conceptual and tied to the verified Library room', () {
      expect(libraryStudySpace.roomId, 'LAB-LIBRARY');
      expect(libraryStudySpace.layoutVerified, isFalse);
      expect(libraryStudySpace.spots, hasLength(12));
      expect(libraryStudySpace.spots.map((s) => s.id).toSet(), hasLength(12));
    });
  });

  group('Focus sessions in app state', () {
    late DateTime now;
    Future<AppState> state() async {
      final s = AppState(
        repo: DemoRepository(seed()),
        auth: null,
        cache: await LocalCache.open(),
        notifications: NotificationService(),
        clock: () => now,
      );
      await s.init();
      return s;
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      now = t0;
    });

    test('an active session survives an app restart with the same remaining time', () async {
      final s1 = await state();
      await s1.startFocus(space: libraryStudySpace, spot: desk, minutes: 25);
      now = at(10);
      await s1.pauseFocus();
      now = at(20);
      final s2 = await state(); // simulated process restart
      expect(s2.activeFocus!.status, FocusStatus.paused);
      expect(s2.activeFocus!.remainingAt(now), const Duration(minutes: 15));
      expect(s2.activeFocus!.spotId, desk.id);
    });

    test('a session that finished while the app was closed moves to history on start-up', () async {
      final s1 = await state();
      await s1.startFocus(space: libraryStudySpace, spot: desk, minutes: 15);
      now = at(60);
      final s2 = await state();
      expect(s2.activeFocus, isNull);
      expect(s2.lastFinishedFocus!.status, FocusStatus.completed);
      expect(s2.focusHistory.single.focusedAt(now), const Duration(minutes: 15));
    });

    test('only one session at a time; ending early records history', () async {
      final s = await state();
      await s.startFocus(space: libraryStudySpace, spot: desk, minutes: 25);
      expect(() => s.startFocus(space: libraryStudySpace, spot: libraryStudySpace.spots[0], minutes: 25), throwsStateError);
      now = at(5);
      await s.endFocus();
      expect(s.activeFocus, isNull);
      expect(s.focusHistory.single.status, FocusStatus.ended);
      expect(s.focusRepo.storageLabel, contains('this device'));
    });

    test('a corrupt stored session is discarded instead of crashing', () async {
      SharedPreferences.setMockInitialValues({'cs.focus.active.v1': '{not json'});
      final repo = LocalFocusRepository(await SharedPreferences.getInstance());
      expect(await repo.loadActive(), isNull);
    });
  });
}
