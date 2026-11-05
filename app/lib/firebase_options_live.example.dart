// TEMPLATE for `firebase_options_live.dart` (that file is git-ignored).
//
// The app needs `lib/firebase_options_live.dart` to compile, even in demo mode,
// because `lib/firebase_options.dart` imports it. Create it in ONE of two ways:
//
//   A) Demo / emulator only (no Firebase project needed):
//        copy lib/firebase_options_live.example.dart lib/firebase_options_live.dart
//      Demo and emulator builds never read these values.
//
//   B) Your own Firebase project (live mode):
//        dart pub global activate flutterfire_cli
//        flutterfire configure --project=<your-project-id> --platforms=android,web \
//          --android-package-name=com.campussync.campussync \
//          --out=lib/firebase_options_live.dart
//      ALWAYS pass --out=lib/firebase_options_live.dart: the default output
//      (lib/firebase_options.dart) is the hand-written backend selector and
//      must not be overwritten.
//
// See README.md, section "Firebase setup".
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Placeholder [FirebaseOptions]. Same API as the FlutterFire-generated file.
class DefaultFirebaseOptions {
  static const _placeholder = 'REPLACE_ME';

  static FirebaseOptions get currentPlatform {
    final options = kIsWeb
        ? web
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => android,
            _ => throw UnsupportedError('CampusSync is configured for Android and web only.'),
          };
    if (options.apiKey == _placeholder || options.projectId == _placeholder) {
      throw StateError(
        'Live mode needs your own Firebase configuration. Run `flutterfire configure '
        '--out=lib/firebase_options_live.dart` (see README.md, "Firebase setup"), '
        'or build without --dart-define=CAMPUSSYNC_BACKEND=live to use demo mode.',
      );
    }
    return options;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _placeholder,
    appId: _placeholder,
    messagingSenderId: _placeholder,
    projectId: _placeholder,
    authDomain: _placeholder,
    storageBucket: _placeholder,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _placeholder,
    appId: _placeholder,
    messagingSenderId: _placeholder,
    projectId: _placeholder,
    storageBucket: _placeholder,
  );
}
