# CampusSync

A Flutter college companion app (Android + web admin dashboard) backed by
Cloud Firestore: timetables, rooms, exams, academic calendar, announcements and
an approval-based student registration flow.

## Repository layout

| Path | Contents |
|---|---|
| `app/` | Flutter application (student app `lib/main.dart`, admin dashboard `lib/main_admin.dart`) |
| `firebase/` | Firestore security rules, indexes, seed and admin-bootstrap scripts, rules tests |
| `e2e/` | End-to-end tests that run against the local Firebase emulators |
| `tools/` | Build, seed-data and device helper scripts |
| `docs/` | Architecture, deployment, security audit, test cases, screenshots |

## Quick start (demo mode, no Firebase needed)

Requirements: Flutter (stable, Dart 3), Android SDK, JDK 17.

```bash
cd app
# 1. Create the (git-ignored) live-options file from the template.
#    Demo and emulator builds never read its values.
cp lib/firebase_options_live.example.dart lib/firebase_options_live.dart
#    Windows: copy lib\firebase_options_live.example.dart lib\firebase_options_live.dart

# 2. Run
flutter pub get
flutter run                      # demo mode: bundled reference data, no network
flutter test
```

`app/android/app/google-services.json` is **not** required for demo or emulator
builds; Gradle skips the Google Services plugin when the file is absent.

## Backends

The backend is chosen explicitly at build time (`app/lib/firebase_options.dart`):

| Command | Backend |
|---|---|
| `flutter run` | Demo: bundled data, nothing saved to a server |
| `flutter run --dart-define=CAMPUSSYNC_BACKEND=emulator` | Firebase Local Emulator Suite (`demo-*` project ids only) |
| `flutter run --dart-define=CAMPUSSYNC_BACKEND=live` | Your own Firebase project (see below) |

## Firebase setup (your own project)

The maintainer's Firebase configuration is not published. To run in live mode,
create your own project:

1. In the [Firebase console](https://console.firebase.google.com), create a
   project, enable **Authentication → Email/Password**, and create a
   **Firestore** database in production mode.
2. Install the CLIs:
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   ```
3. Generate the client configuration from `app/`:
   ```bash
   flutterfire configure --project=<your-project-id> --platforms=android,web \
     --android-package-name=com.campussync.campussync \
     --out=lib/firebase_options_live.dart
   ```
   **Always pass `--out=lib/firebase_options_live.dart`.** The default output
   (`lib/firebase_options.dart`) is the hand-written backend selector and must
   not be overwritten. This writes `lib/firebase_options_live.dart`,
   `android/app/google-services.json` and `firebase.json`, all git-ignored.
4. Test and deploy the security rules **before** anyone registers:
   ```bash
   cd firebase
   npm install
   npm run test:rules
   npx firebase use --add
   npx firebase deploy --only firestore:rules,firestore:indexes
   ```
5. Seed reference data and create the first administrator: see
   [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) §3, steps 7–8.
6. Restrict your API keys in Google Cloud Console → Credentials (Android
   package name + SHA-1 certificate fingerprint; HTTP referrers for web).

Firebase **client** configuration (API key, app id, project id) identifies a
project but is not a secret; access is enforced by the Firestore rules. Admin
SDK **service-account keys are secrets**: keep them outside the repository
(`GOOGLE_APPLICATION_CREDENTIALS`) or use `gcloud auth application-default login`.

## Release builds

Release APKs are published as GitHub Release assets, not committed.
`app/android/app/build.gradle.kts` currently signs release builds with the
**debug key**. For a distributable build, create a keystore outside the
repository, reference it from `app/android/key.properties` (git-ignored) and add
a release `signingConfig`; see
[Flutter: Build and release an Android app](https://docs.flutter.dev/deployment/android).

## License

[MIT](LICENSE)
