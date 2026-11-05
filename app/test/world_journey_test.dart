import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/domain/focus.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:campussync/ui/home/home_shell.dart';
import 'package:campussync/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> seed() => {
  for (final f in Directory('assets/seed').listSync().whereType<File>())
    f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
};

void main() {
  testWidgets('Campus → Academic Block → floor → room → Library → desk → focus session → back to campus', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    // Reduced motion keeps the test deterministic (no looping animations).
    SharedPreferences.setMockInitialValues({
      'cs.prefs.v1': jsonEncode({'reduceMotion': true}),
    });
    var now = DateTime(2026, 10, 21, 9, 0);
    final state = await tester.runAsync(() async {
      final s = AppState(
        repo: DemoRepository(seed()),
        auth: null,
        cache: await LocalCache.open(),
        notifications: NotificationService(),
        clock: () => now,
      );
      await s.init();
      await s.chooseDemoProfile(groupId: 'btech-computer-2026-27-sem5-div-b', batch: 'B1', name: 'Tester');
      return s;
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state!,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Enter the Academic Block from its campus signpost.
    await tester.tap(find.text('Academic Block'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Floor plans from the supplied MPSTME layouts'), findsOneWidget);

    // 2. Ride the lift to Floor 4 and select CR 402 (real room, real status).
    await tester.tap(find.widgetWithText(ChoiceChip, '4'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Main Computer Engineering department floor'), findsOneWidget);
    await tester.tap(find.text('CR 402'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Scheduled use on'), findsOneWidget);
    expect(find.textContaining('Based on published timetables only'), findsOneWidget);
    Navigator.of(tester.element(find.textContaining('Scheduled use on'))).pop(); // close the room sheet
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.textContaining('Scheduled use on'), findsNothing);

    // 3. Floor 7 has the Library; enter it.
    final liftPanel = find.ancestor(of: find.widgetWithText(ChoiceChip, '4'), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, '7'), 120, scrollable: liftPanel);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '7'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ChoiceChip, '7'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Enter library'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Study hall'), findsOneWidget);
    expect(find.textContaining('desk positions are not surveyed'), findsOneWidget);
    expect(find.text('Tap a desk to sit down.'), findsOneWidget);

    // 4. Choose Desk 4: the character walks there and sits.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Desk 4(\D|$)')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Seated at Desk 4'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Your character, sitting')), findsOneWidget);

    // 5. Start a 25-minute session; the countdown follows the clock.
    await tester.tap(find.text('Start 25-minute focus'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('FOCUSING'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    now = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('15:00'), findsOneWidget);

    // Other desks are locked during a session.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Desk 1(\D|$)')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('End your current session before moving to another desk.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    // 6. Pause: time freezes. Resume continues.
    await tester.tap(find.text('Pause'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('PAUSED'), findsOneWidget);
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('15:00'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('FOCUSING'), findsOneWidget);

    // 7. Let it run to completion.
    now = now.add(const Duration(minutes: 15, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Session complete'), findsOneWidget);
    expect(state.focusHistory.single.status, FocusStatus.completed);
    expect(find.textContaining('25 of 25 min · completed'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Seated at Desk 4'), findsOneWidget);

    // 8. Back to campus, then the existing academic screens still work.
    await tester.tap(find.byTooltip('Back to campus'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Today on campus'), findsOneWidget);
    await tester.tap(find.text('Timetable').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Day'), findsOneWidget);
    semantics.dispose();
  });
}
