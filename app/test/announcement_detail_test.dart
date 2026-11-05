import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/domain/models.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:campussync/ui/theme.dart';
import 'package:campussync/ui/updates/announcement_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> seed() => {
  for (final f in Directory('assets/seed').listSync().whereType<File>())
    f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
};

void main() {
  Future<void> pumpDetail(WidgetTester tester, Announcement a) async {
    SharedPreferences.setMockInitialValues({});
    final state = (await tester.runAsync(
      () async => AppState(repo: DemoRepository(seed()), auth: null, cache: await LocalCache.open(), notifications: NotificationService()),
    ))!;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: AnnouncementDetail(announcement: a)),
      ),
    );
    await tester.pump();
  }

  final today = DateTime.now();
  FilledButton linkButton(WidgetTester tester) => tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));

  testWidgets('a link on a current announcement is labelled neutrally, never as an open registration', (tester) async {
    // Like the live ICPC and Qiskit notices: registration closed, event still current, official page linked.
    await pumpDetail(
      tester,
      Announcement(
        id: 'a1',
        title: 'Event with closed registration',
        status: PublishStatus.published,
        description: 'Registration closed on 21 October.',
        startDate: today.subtract(const Duration(days: 1)),
        endDate: today.add(const Duration(days: 2)),
        registrationUrl: 'https://example.org/event',
      ),
    );
    expect(find.text('Open official link'), findsOneWidget);
    expect(find.textContaining('registration link', findRichText: true), findsNothing);
    expect(find.text('Opens example.org in your browser.'), findsOneWidget);
    expect(linkButton(tester).onPressed, isNotNull);
  });

  testWidgets('an ended announcement disables its link and says it has ended', (tester) async {
    await pumpDetail(
      tester,
      Announcement(
        id: 'a2',
        title: 'Past event',
        status: PublishStatus.published,
        endDate: today.subtract(const Duration(days: 3)),
        registrationUrl: 'https://example.org/past',
      ),
    );
    expect(find.text('This announcement has ended.'), findsOneWidget);
    expect(linkButton(tester).onPressed, isNull);
  });

  testWidgets('an announcement with only a title renders without optional fields or a link button', (tester) async {
    await pumpDetail(tester, const Announcement(id: 'a3', title: 'Bare notice', status: PublishStatus.published));
    expect(find.text('Bare notice'), findsOneWidget);
    expect(find.text('No further details were provided.'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an image URL that cannot be decoded (e.g. SVG) does not break the page', (tester) async {
    await pumpDetail(
      tester,
      const Announcement(
        id: 'a4',
        title: 'With image',
        status: PublishStatus.published,
        imageUrl: 'https://news.example.org/logo.svg',
        summary: 'Summary only.',
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Summary only.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
