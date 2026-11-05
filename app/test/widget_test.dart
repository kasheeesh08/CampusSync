import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/main.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> demoState() async {
  SharedPreferences.setMockInitialValues({});
  final seed = {
    for (final f in Directory('assets/seed').listSync().whereType<File>())
      f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
  };
  final s = AppState(repo: DemoRepository(seed), auth: null, cache: await LocalCache.open(), notifications: NotificationService());
  await s.init();
  return s;
}

void main() {
  testWidgets('Demo onboarding validates input and opens the campus home', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final state = await tester.runAsync(demoState);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state!, child: const CampusSyncApp()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Explore the demo'), findsOneWidget);
    await tester.tap(find.text('Explore the demo'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

    // Submitting empty form shows validation messages.
    await tester.tap(find.text('Enter campus'));
    await tester.pump();
    expect(find.text('Name is required.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Tester');
    await tester.tap(find.text('B.Tech Computer · Sem V · Div B'));
    await tester.pump();
    await tester.tap(find.text('B1'));
    await tester.pump();
    await tester.tap(find.text('Enter campus'));
    await tester.pump(const Duration(seconds: 1));

    expect(state.profile?.groupId, 'btech-computer-2026-27-sem5-div-b');
    expect(find.textContaining('Tester'), findsWidgets);
    expect(find.text('Timetable'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });
}
