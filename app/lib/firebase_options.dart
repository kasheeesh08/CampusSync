import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options_live.dart';

/// Which backend this build talks to. Chosen explicitly at build time and
/// shown in the UI, so demo or test data is never mistaken for live data.
enum Backend {
  /// Bundled reference data, no network. Default for tests and plain builds.
  demo,

  /// Firebase Local Emulator Suite (project `demo-campussync`); never production.
  emulator,

  /// Your own Firebase project, configured in `firebase_options_live.dart`.
  live,
}

/// Backend selection:
///
///   flutter run                                         -> demo (default)
///   flutter run --dart-define=CAMPUSSYNC_BACKEND=emulator -> local emulators
///   flutter run --dart-define=CAMPUSSYNC_BACKEND=live     -> your Firebase project
///
/// `--dart-define=USE_FIREBASE_EMULATOR=true` is still accepted for the
/// existing emulator workflow. Live options come from the FlutterFire-generated
/// `firebase_options_live.dart` (`flutterfire configure`), never hand-typed.
/// That file is git-ignored; see `firebase_options_live.example.dart`.
class FirebaseConfig {
  static const _backendDefine = String.fromEnvironment('CAMPUSSYNC_BACKEND');
  static const _legacyEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
  static const _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  // Overridable so tests can use a dedicated emulator instead of a shared one.
  static const firestoreEmulatorPort = int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8080);
  static const authEmulatorPort = int.fromEnvironment('AUTH_EMULATOR_PORT', defaultValue: 9099);
  static const _emulatorProject = String.fromEnvironment('FIREBASE_EMULATOR_PROJECT', defaultValue: 'demo-campussync');

  /// Only "demo-" project ids: the emulators never forward those to production.
  static String get emulatorProjectId => _emulatorProject.startsWith('demo-')
      ? _emulatorProject
      : throw StateError('FIREBASE_EMULATOR_PROJECT must start with "demo-" (got "$_emulatorProject").');

  static Backend get backend => switch (_backendDefine) {
    'live' => Backend.live,
    'emulator' => Backend.emulator,
    'demo' || '' => _legacyEmulator ? Backend.emulator : Backend.demo,
    _ => throw StateError('Unknown CAMPUSSYNC_BACKEND "$_backendDefine" (use demo, emulator or live).'),
  };

  static bool get useEmulator => backend == Backend.emulator;
  static bool get isConfigured => backend != Backend.demo;

  /// Android emulators reach the host machine at 10.0.2.2.
  static String get emulatorHost =>
      _emulatorHost.isNotEmpty ? _emulatorHost : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : '127.0.0.1');

  static FirebaseOptions get options => switch (backend) {
    // Placeholder values accepted by the emulators; "demo-" projects cannot reach production.
    Backend.emulator => FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: kIsWeb ? '1:000000000000:web:0000000000000000' : '1:000000000000:android:0000000000000000',
      messagingSenderId: '000000000000',
      projectId: emulatorProjectId,
    ),
    Backend.live => DefaultFirebaseOptions.currentPlatform,
    Backend.demo => throw StateError('Demo mode does not use Firebase.'),
  };
}
