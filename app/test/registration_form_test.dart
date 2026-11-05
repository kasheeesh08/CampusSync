import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/auth_service.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/data/registration_errors.dart';
import 'package:campussync/domain/models.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:campussync/ui/onboarding/auth_screens.dart';
import 'package:campussync/ui/theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auth double: never touches Firebase; records registration attempts.
class FakeAuth extends AuthService {
  final _ctrl = StreamController<AuthUser?>.broadcast();
  int registerCalls = 0;
  AuthUser? _user;
  @override
  AuthUser? get current => _user;
  @override
  Stream<AuthUser?> changes() => _ctrl.stream;
  @override
  Future<AuthUser> register(String email, String password) async {
    registerCalls++;
    return _user = AuthUser('uid-$registerCalls', email.trim(), false);
  }

  /// Simulates the student opening the verification link, then "I have verified".
  void verify() => _ctrl.add(_user = AuthUser(_user!.uid, _user!.email, true));

  /// A restored session whose email is still unverified.
  void emitUnverified() => _ctrl.add(_user);
  @override
  Future<AuthUser?> reload() async => _user;
}

class LiveLikeRepo extends DemoRepository {
  LiveLikeRepo(super.seed, {this.groups});

  /// Replaces the division list the server would return (null: seeded groups).
  final Future<List<AcademicGroup>> Function()? groups;
  @override
  bool get isDemo => false;
  @override
  Future<List<AcademicGroup>> registrationGroups() => groups?.call() ?? super.registrationGroups();
}

Map<String, dynamic> seed() => {
  for (final f in Directory('assets/seed').listSync().whereType<File>())
    f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
};

void main() {
  late FakeAuth auth;
  late LiveLikeRepo repo;
  late AppState state;

  Future<void> pumpForm(WidgetTester tester, {Future<List<AcademicGroup>> Function()? groups}) async {
    await tester.binding.setSurfaceSize(const Size(520, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    repo = LiveLikeRepo(seed(), groups: groups);
    auth = FakeAuth();
    state = (await tester.runAsync(() async {
      final s = AppState(repo: repo, auth: auth, cache: await LocalCache.open(), notifications: NotificationService());
      await s.init();
      return s;
    }))!;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const RegisterScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> fillValid(WidgetTester tester, {String sap = '99999300123'}) async {
    await tester.enterText(field('Full name *'), 'Test Student');
    await tester.enterText(field('Email *'), 'student1@campussync.test');
    await tester.enterText(field('SAP ID *'), sap);
    await tester.tap(find.text('Select your division'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B.Tech Computer · Sem V · Div B').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Roll number *'), 'B010');
    await tester.tap(find.text('Select your lab batch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batch B1').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Password *'), 'Campus2026');
    await tester.enterText(field('Confirm password *'), 'Campus2026');
    await tester.pump();
  }

  /// Step 1 (create account), then email verification, then the app shows a
  /// fresh "Complete your profile" form, as main.dart does for needsProfile.
  Future<void> signUpAndVerify(WidgetTester tester, {String sap = '99999300124'}) async {
    await fillValid(tester, sap: sap);
    await tester.tap(find.text('Create account'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    auth.verify();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const RegisterScreen(key: ValueKey('after-verify'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Editing one field does not show errors on untouched fields', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Email *'), 'student@');
    await tester.pump();
    expect(find.textContaining('Enter a valid email address'), findsOneWidget);
    expect(find.text('Name is required.'), findsNothing);
    expect(find.text('SAP ID is required.'), findsNothing);
    expect(find.text('Password is required.'), findsNothing);
  });

  testWidgets('Correcting a field clears its error', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Email *'), 'student@');
    await tester.pump();
    expect(find.textContaining('Enter a valid email address'), findsOneWidget);
    await tester.enterText(field('Email *'), 'student@campussync.test');
    await tester.pump();
    expect(find.textContaining('Enter a valid email address'), findsNothing);
  });

  testWidgets('Malformed identifiers are rejected with field-specific messages', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('SAP ID *'), '70022A001');
    await tester.tap(find.text('Select your division'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B.Tech Computer · Sem V · Div B').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Roll number *'), 'C001');
    await tester.pump();
    expect(find.text('SAP ID must contain digits only.'), findsOneWidget);
    expect(find.text('Roll number should start with B for Division B.'), findsOneWidget);
  });

  testWidgets('Submitting an empty form is blocked and lists every required field', (tester) async {
    await pumpForm(tester);
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('SAP ID is required.'), findsOneWidget);
    expect(find.text('Select your academic group.'), findsOneWidget);
    expect(find.text('Roll number is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
    expect(auth.registerCalls, 0, reason: 'invalid forms must not reach the backend');
  });

  testWidgets('Creating an account saves no profile or SAP ID claim before the email is verified', (tester) async {
    await pumpForm(tester);
    await fillValid(tester, sap: '99999300124');
    await tester.tap(find.text('Create account'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(auth.registerCalls, 1);
    expect(await tester.runAsync(() => repo.loadProfile('uid-1')), isNull);
    expect(state.registrationDraft?.sapId, '99999300124', reason: 'details are kept for after verification');
  });

  testWidgets('After verification the prefilled form submits once with normalised values and the sign-in email', (tester) async {
    await pumpForm(tester);
    await signUpAndVerify(tester);
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '99999300124'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'B010'), findsOneWidget);
    await tester.tap(find.text('Submit for approval'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(auth.registerCalls, 1);
    final saved = await tester.runAsync(() => repo.loadProfile('uid-1'));
    expect(saved!.sapId, '99999300124');
    expect(saved.rollNumber, 'B010');
    expect(saved.email, 'student1@campussync.test');
    expect(saved.status, AccountStatus.pending);
    expect(saved.requestedGroupId, 'btech-computer-2026-27-sem5-div-b');
    expect(state.registrationDraft, isNull);
  });

  testWidgets('An unverified account is refused before any SAP ID lookup or write', (tester) async {
    await pumpForm(tester);
    await fillValid(tester, sap: '99999300125');
    await tester.tap(find.text('Create account'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    auth.emitUnverified(); // e.g. app restarted before the link was opened
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    Object? error;
    await tester.runAsync(() async {
      try {
        await state.register(
          email: '', password: '', displayName: 'Test Student', sapId: '99999300125', rollNumber: 'B010',
          requestedGroupId: 'btech-computer-2026-27-sem5-div-b',
        );
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<RegistrationException>().having((e) => e.kind, 'kind', RegistrationFailure.unverifiedEmail));
    expect(await tester.runAsync(() => repo.loadProfile('uid-1')), isNull);
    // The SAP ID was not claimed: another account can still register it.
    await tester.runAsync(
      () => repo.registerProfile(const StudentProfile(uid: 'other', email: 'o@x.test', displayName: 'O', sapId: '99999300125', rollNumber: 'B011')),
    );
  });

  testWidgets('A rejected registration (SAP ID already claimed) is reported and the form stays open', (tester) async {
    await pumpForm(tester);
    await tester.runAsync(
      () => repo.registerProfile(
        const StudentProfile(uid: 'someone-else', email: 'x@y.test', displayName: 'X', sapId: '99999300123', rollNumber: 'B099'),
      ),
    );
    await signUpAndVerify(tester, sap: '99999300123');
    await tester.tap(find.text('Submit for approval'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('An account with this SAP ID already exists.'), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(await tester.runAsync(() => repo.loadProfile('uid-1')), isNull);
  });

  group('Academic groups unavailable', () {
    const setup = "Registration isn't open yet: no academic groups are configured. Please contact the CampusSync administrator.";
    const network = 'Could not reach the server to load academic groups. Check your internet connection.';
    bool submitEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

    testWidgets('an empty list from the server shows the setup message, not a connection error', (tester) async {
      await pumpForm(tester, groups: () async => const []);
      expect(find.text(setup), findsOneWidget);
      expect(find.text(network), findsNothing);
      expect(submitEnabled(tester), isFalse);
    });

    testWidgets('no connection (offline, nothing cached) shows the network error', (tester) async {
      await pumpForm(tester, groups: () async => checkedRegistrationGroups(const [], fromCache: true));
      expect(find.text(network), findsOneWidget);
      expect(find.text(setup), findsNothing);
      expect(submitEnabled(tester), isFalse);
    });

    testWidgets('a Firestore "unavailable" error shows the network error', (tester) async {
      await pumpForm(tester, groups: () => Future.error(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')));
      expect(find.text(network), findsOneWidget);
      expect(find.text(setup), findsNothing);
    });

    testWidgets('other failures are not blamed on the connection and keep their code', (tester) async {
      await pumpForm(tester, groups: () => Future.error(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')));
      expect(find.text('Academic groups could not be loaded (permission-denied). Try again or contact the administrator.'), findsOneWidget);
      expect(find.text(network), findsNothing);
      expect(find.text(setup), findsNothing);
    });

    testWidgets('Retry loads the groups once they have been configured', (tester) async {
      var configured = false;
      final seeded = LiveLikeRepo(seed()).registrationGroups;
      await pumpForm(tester, groups: () => configured ? seeded() : Future.value(const <AcademicGroup>[]));
      expect(find.text(setup), findsOneWidget);
      configured = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text(setup), findsNothing);
      expect(submitEnabled(tester), isTrue);
    });
  });
}
