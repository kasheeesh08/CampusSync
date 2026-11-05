import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/data/repository.dart';
import 'package:campussync/domain/models.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:campussync/ui/admin/admin_people.dart';
import 'package:campussync/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const squatter = StudentProfile(uid: 'sq', email: 'squatter@campussync.test', displayName: 'Sam Squatter', sapId: '99999300123', rollNumber: 'B001');
const released = StudentProfile(uid: 'rel', email: 'released@campussync.test', displayName: 'Rae Released', sapId: '99999300456', rollNumber: 'B002');
const actor = Actor('demo-admin', 'demo-admin@local');

void main() {
  late DemoRepository repo;

  Future<void> pumpStudents(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    repo = DemoRepository({
      for (final f in Directory('assets/seed').listSync().whereType<File>())
        f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
    });
    final state = await tester.runAsync(() async {
      await repo.registerProfile(squatter);
      await repo.registerProfile(released);
      await repo.releaseSapId(released, actor);
      final s = AppState(repo: repo, auth: null, cache: await LocalCache.open(), notifications: NotificationService(), adminApp: true);
      await s.init();
      return s;
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state!,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: AdminStudents())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cardOf(String name) => find.ancestor(of: find.text(name, findRichText: true).first, matching: find.byType(Card));
  Finder inCard(String name, String text) => find.descendant(of: cardOf(name), matching: find.text(text));

  testWidgets('Release SAP ID is offered only for accounts that still hold their claim', (tester) async {
    await pumpStudents(tester);
    expect(find.textContaining('Sam Squatter'), findsOneWidget);
    expect(inCard('Sam Squatter · B001', 'Release SAP ID'), findsOneWidget);
    expect(inCard('Sam Squatter · B001', 'Approve'), findsOneWidget);

    await tester.tap(find.text('suspended (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rae Released'), findsOneWidget);
    expect(find.textContaining('SAP ID released: this account no longer holds 99999300456'), findsOneWidget);
    expect(inCard('Rae Released · B002', 'Release SAP ID'), findsNothing);
    expect(inCard('Rae Released · B002', 'Approve'), findsNothing, reason: 'a released account cannot be approved');
  });

  testWidgets('Releasing again from a stale card reports "already released" and changes nothing', (tester) async {
    await pumpStudents(tester);
    // Another admin releases the squatter while this list is still on screen.
    await tester.runAsync(() => repo.releaseSapId(squatter, actor));
    final audits = (await tester.runAsync(() => repo.listAudit()))!.length;

    await tester.tap(inCard('Sam Squatter · B001', 'Release SAP ID'));
    await tester.pumpAndSettle();
    expect(find.text('Release SAP ID 99999300123?'), findsOneWidget, reason: 'confirmation is still required');
    await tester.tap(find.text('Suspend and release'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.textContaining('was already released for squatter@campussync.test. Nothing changed.'), findsOneWidget);
    expect(find.textContaining('Failed'), findsNothing);
    expect((await tester.runAsync(() => repo.listAudit()))!.length, audits, reason: 'no duplicate audit record');
    await tester.pumpAndSettle();
    expect(find.textContaining('Sam Squatter'), findsNothing, reason: 'the list reloads; the account is no longer pending');
  });
}
