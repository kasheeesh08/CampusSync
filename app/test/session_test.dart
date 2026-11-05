import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/auth_service.dart';
import 'package:campussync/data/campus_data.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/data/repository.dart';
import 'package:campussync/domain/models.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auth double that never touches Firebase.
class FakeAuth extends AuthService {
  final _ctrl = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  @override
  AuthUser? get current => _user;
  @override
  Stream<AuthUser?> changes() => _ctrl.stream;
  void emit(AuthUser? u) {
    _user = u;
    _ctrl.add(u);
  }
}

/// Demo data behind a "live" repository flag, so AppState takes the signed-in path.
class LiveLikeRepo extends DemoRepository {
  LiveLikeRepo(super.seed);
  @override
  bool get isDemo => false;
}

Map<String, dynamic> seed() => {
  for (final f in Directory('assets/seed').listSync().whereType<File>())
    f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
};

void main() {
  test('Regression: a persisted sign-in loads data on cold start without a manual refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LiveLikeRepo(seed());
    await repo.registerProfile(
      const StudentProfile(uid: 'u1', email: 's@x.test', displayName: 'S', sapId: '99999300123', rollNumber: 'B010'),
    );
    await repo.setStudentAccount(
      'u1',
      status: AccountStatus.active,
      groupId: 'btech-computer-2026-27-sem5-div-b',
      actor: const Actor('a1', 'a@x.test'),
    );
    final auth = FakeAuth();
    final s = AppState(repo: repo, auth: auth, cache: await LocalCache.open(), notifications: NotificationService());
    await s.init();
    expect(s.stage, SessionStage.loading);
    auth.emit(const AuthUser('u1', 's@x.test', true)); // persisted session restored at startup
    await pumpEventQueue();
    expect(s.stage, SessionStage.ready);
    expect(s.data, isNotNull, reason: 'initial fetch must run when the session is restored');
    expect(s.data!.origin, DataOrigin.bundledDemo);
    expect(s.myExams.map((e) => e.subjectCode), ['OR', 'AI', 'SE', 'OS', 'IVP']);
  });

  test('Pending accounts do not fetch academic data', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LiveLikeRepo(seed());
    await repo.registerProfile(
      const StudentProfile(uid: 'u2', email: 'p@x.test', displayName: 'P', sapId: '99999300124', rollNumber: 'B011'),
    );
    final auth = FakeAuth();
    final s = AppState(repo: repo, auth: auth, cache: await LocalCache.open(), notifications: NotificationService());
    await s.init();
    auth.emit(const AuthUser('u2', 'p@x.test', true));
    await pumpEventQueue();
    expect(s.stage, SessionStage.pendingApproval);
    expect(s.data, isNull);
  });

  test('Refresh picks up an admin group reassignment; a batch from the old group is ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LiveLikeRepo(seed());
    const admin = Actor('a1', 'a@x.test');
    await repo.registerProfile(
      const StudentProfile(uid: 'u3', email: 'g@x.test', displayName: 'G', sapId: '99999300125', rollNumber: 'B012', batch: 'B1'),
    );
    await repo.setStudentAccount('u3', status: AccountStatus.active, groupId: 'btech-computer-2026-27-sem5-div-b', actor: admin);
    final auth = FakeAuth();
    final s = AppState(repo: repo, auth: auth, cache: await LocalCache.open(), notifications: NotificationService());
    await s.init();
    auth.emit(const AuthUser('u3', 'g@x.test', true));
    await pumpEventQueue();
    expect(s.myGroup!.division, 'B');
    expect(s.scheduleProfile!.batch, 'B1');

    await repo.setStudentAccount('u3', status: AccountStatus.active, groupId: 'btech-computer-2026-27-sem5-div-c', actor: admin);
    await s.refresh();
    expect(s.myGroup!.division, 'C', reason: 'group change must apply on refresh');
    expect(s.scheduleProfile!.batch, isNull, reason: 'B1 is not a Div C batch');
    final monday = DateTime(2026, 7, 20);
    expect(s.schedule!.entriesOn(s.scheduleProfile!, monday).first.subjectCode, 'MAD'); // Div C Mon 08:00, not Div B labs
  });

  test('Refresh after suspension stops at the suspended gate and fetches nothing new', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LiveLikeRepo(seed());
    const admin = Actor('a1', 'a@x.test');
    await repo.registerProfile(
      const StudentProfile(uid: 'u4', email: 's2@x.test', displayName: 'S', sapId: '99999300126', rollNumber: 'B013'),
    );
    await repo.setStudentAccount('u4', status: AccountStatus.active, groupId: 'btech-computer-2026-27-sem5-div-b', actor: admin);
    final auth = FakeAuth();
    final s = AppState(repo: repo, auth: auth, cache: await LocalCache.open(), notifications: NotificationService());
    await s.init();
    auth.emit(const AuthUser('u4', 's2@x.test', true));
    await pumpEventQueue();
    final before = s.data!.syncedAt;
    await repo.setStudentAccount('u4', status: AccountStatus.suspended, groupId: 'btech-computer-2026-27-sem5-div-b', actor: admin);
    await s.refresh();
    expect(s.stage, SessionStage.suspended);
    expect(s.data!.syncedAt, before, reason: 'no academic fetch after suspension');
  });
}
