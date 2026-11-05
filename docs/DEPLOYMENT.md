# CampusSync – Setup and Deployment

## 1. Prerequisites
- Flutter 3.47.x (cloned at `<flutter-sdk>`; add `<flutter-sdk>\bin` to PATH)
- Android Studio with Android SDK (API 34+); for licence acceptance, install *Android SDK Command-line Tools* via SDK Manager
- Node.js 18+ (seed script), Firebase CLI (`npm i -g firebase-tools`) for rules and hosting

## 2. Run in demo mode (no backend)
```bash
cd app
flutter pub get
flutter run                                  # student app on emulator/phone
flutter run -d chrome -t lib/main_admin.dart # admin dashboard
flutter test                                 # unit + widget tests
```
Demo mode is labelled in the UI. It uses the bundled reference data, and admin edits last only for the session.

## 2a. Local end-to-end testing with the Firebase Local Emulator Suite (no cloud project)
Requires Java 17+ and Node 18+. All tooling is project-local, in `firebase/node_modules`.
```powershell
cd <repo>\firebase
npm install                                   # first time only
# These two start their own temporary emulators on ports 8080/9099, so run them
# BEFORE `emulators:start` below (or while no other emulator uses those ports).
npm run test:rules                            # 61 allow/deny security-rule tests
npm run test:seed                             # 9 seed / first-admin safeguard tests
npx firebase emulators:start --only auth,firestore --project demo-campussync
# second terminal: seed reference data + test staff accounts (emulator only)
$env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"; $env:FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099"
node seed_firestore.mjs --project demo-campussync --emulator-test-users
# third terminal: app in emulator mode (Android emulator reaches the host at 10.0.2.2)
cd ..\app; flutter run -d emulator-5554 --dart-define=CAMPUSSYNC_BACKEND=emulator
flutter run -d chrome -t lib/main_admin.dart --web-port 8767 --dart-define=CAMPUSSYNC_BACKEND=emulator
```
Test accounts (emulator only): `admin@campussync.test` / `Admin12345` (admin) and `content@campussync.test` / `Content12345` (content manager). The emulator doesn't send emails; open the verification link printed in the emulator log. Emulator data is lost when the emulators stop.

**Emulator endpoint flags** (build time; defaults shown):
- `--dart-define=FIREBASE_EMULATOR_HOST=…`: default `10.0.2.2` on Android, `127.0.0.1` elsewhere. In the Android emulator, `10.0.2.2` is the development machine; `127.0.0.1` would be the phone itself.
- `--dart-define=FIRESTORE_EMULATOR_PORT=8080` and `--dart-define=AUTH_EMULATOR_PORT=9099`.
- `--dart-define=FIREBASE_EMULATOR_PROJECT=demo-campussync`: must start with `demo-`, otherwise the app refuses to start.

The emulator banner shows the project, host and port the build uses.

Android: Firebase is initialised only from Dart. `FirebaseInitProvider` is removed in `android/app/src/main/AndroidManifest.xml`, because otherwise Android auto-creates the default app from `google-services.json` (live project) and emulator mode fails with `[core/duplicate-app]`.

Local ports:

| Port | Use |
|---|---|
| 8080 / 9099 | Firestore / Auth emulator (§2a) |
| 8180 / 9180 | Dedicated E2E emulator (`run_isolated.mjs`, §2b) |
| 8765 | Admin web build (static, §2b) |
| 8766 | Student web build (static, §2b) |
| 8767 | Admin dashboard via `flutter run` (§2a, §3) |

On Windows the Firestore emulator JVM can outlive `emulators:exec`. If port 8080 is busy, first check what holds it (`Get-NetTCPConnection -LocalPort 8080`, then the process command line). If it is a running `emulators:start` session that you or a teammate are using, leave it alone: stopping it discards that emulator's data. Stop only an orphaned `cloud-firestore-emulator` java process that no `firebase emulators:*` command owns.

## 2b. Chrome E2E checks (dedicated, temporary emulator)
The suites delete and re-seed emulator data, so they run against a **dedicated** emulator started just for the run, never against the §2a session. No §2a emulator is needed.
```powershell
cd <repo>\app
flutter build web -t lib/main_admin.dart --dart-define=CAMPUSSYNC_BACKEND=emulator --dart-define=FIRESTORE_EMULATOR_PORT=8180 --dart-define=AUTH_EMULATOR_PORT=9180 --dart-define=FIREBASE_EMULATOR_PROJECT=demo-campussync-e2e --profile --output build/web_admin_e2e
flutter build web -t lib/main.dart --dart-define=CAMPUSSYNC_BACKEND=emulator --dart-define=FIRESTORE_EMULATOR_PORT=8180 --dart-define=AUTH_EMULATOR_PORT=9180 --dart-define=FIREBASE_EMULATOR_PROJECT=demo-campussync-e2e --profile --output build/web_student_e2e
cd build\web_admin_e2e; python -m http.server 8765        # leave running
# new terminal
cd <repo>\app\build\web_student_e2e; python -m http.server 8766
# new terminal
cd <repo>\e2e; npm install    # first time (puppeteer-core only; uses installed Chrome)
node run_isolated.mjs                                      # 4 suites, 81 checks
```
`run_isolated.mjs`:
- refuses to start if 8180/9180 (or its hub/logging ports) are already in use;
- writes a temporary emulator config outside the repo;
- runs `run_all.mjs` inside `firebase emulators:exec` with project `demo-campussync-e2e`;
- afterwards stops only an emulator JVM left on its own port.

Safety:
- The E2E scripts (`env.mjs`) refuse to run unless `E2E_FIRESTORE_HOST`/`E2E_AUTH_HOST` are set to a local host, refuse the shared ports 8080/9099 (unless `E2E_ALLOW_SHARED_EMULATOR=1`), and refuse non-`demo-` projects.
- Each Chrome page has a **network interlock** (`lib.mjs`). Requests to Firebase production hosts, or to any local port other than the web builds and the configured emulator, are aborted and fail the suite (check `NET`). For example, a stale build compiled for 8080 is caught before it can write to the §2a emulator.
- All records the suites create are labelled TEST/QA.

## 3. Connect your own Firebase project
App-side configuration is per developer and is **not in the repository**: `app/android/app/google-services.json` and `app/lib/firebase_options_live.dart` are git-ignored and must be generated for your own project (steps 4–5; template: `app/lib/firebase_options_live.example.dart`). `--dart-define=CAMPUSSYNC_BACKEND=live` selects them. Default builds and all tests stay in demo mode. **Live connectivity has not been verified yet**; the console steps below are still required. Stay on the Spark (free) plan.
1. **Create or select the project:** <https://console.firebase.google.com> → Add project (or pick the one the college/team is authorised to use). The project stays on the Spark (free) plan: don't enable billing or upgrade to Blaze. Server-side push notifications would need Cloud Functions (Blaze) and are out of scope.
2. **Authentication:** Build → Authentication → Sign-in method → enable **Email/Password**. Under Settings → Authorised domains, add the admin hosting domain later (§4).
3. **Firestore:** Build → Firestore Database → Create database → **production mode**, region `asia-south1` (Mumbai).
4. **Register apps:** Project settings → Your apps:
   - Android app, package `com.campussync.campussync`; download `google-services.json` into `app/android/app/` (git-ignored).
   - Web app for the admin dashboard (registered by `flutterfire configure`; check Project settings for duplicate web apps and remove unused ones).
5. **App options (generated, never hand-typed):** to regenerate, from `app/` run
   `flutterfire configure --project=<your-project-id> --platforms=android,web --android-package-name=com.campussync.campussync --out=lib/firebase_options_live.dart`.
   Always pass `--out=lib/firebase_options_live.dart`: the default output (`lib/firebase_options.dart`) is the hand-written backend selector and must not be overwritten. These values identify the project but aren't secrets; access is enforced by the rules. Optionally restrict the API keys in Google Cloud Console → Credentials (Android package + SHA-1; web HTTP referrers); this is free.
6. **Review, then deploy the rules** (they are covered by `firebase/test/rules.test.mjs`, 61/61 passing). Deploy them **before** anyone registers. `npm run test:rules` needs ports 8080/9099 free (see §2a):
   ```powershell
   cd <repo>\firebase
   npx firebase login
   npx firebase use --add          # choose the project; alias "default"
   npm run test:rules              # must pass before deploying
   npx firebase deploy --only firestore:rules,firestore:indexes
   ```
   What the rules require from data (all app writes and the seed already comply):
   - **Announcements and exams** need `audienceKeys` (`all`, `group:<id>`, `dept:<id>`, `oe:<id>`, derived from their audience). A student can read only records whose keys match their own group, department or chosen electives (SECURITY_AUDIT M2), and student queries must include `audienceKeys array-contains-any`. The two composite indexes this needs are in `firebase/firestore.indexes.json` and deploy with the command above.
   - **Staff writes** need an `auditId` naming an audit record created in the same commit (M4). Documents created by hand in the Console bypass the rules but won't be visible to students without `audienceKeys`.
   - **No migration is needed for a new project**: it has no data yet. An emulator session seeded before this change has exams without `audienceKeys`, so students see no exams there. The create-only seed won't add the field to existing documents; start that emulator fresh instead.
7. **Seed the reference data** (rooms, floors, timetables, exams, calendar). Until this is done, the live app's registration screen shows "Registration isn't open yet: no academic groups are configured." The server answered, but `groups` has no active divisions. Without a connection it shows a network error instead. The seed is **create-only**: existing documents are never overwritten, so re-running it never undoes admin edits. It never writes announcements, import provenance, students, SAP claims or roles. Live writes need the project id repeated in `--confirm-live`:
   ```powershell
   node seed_firestore.mjs --project <your-project-id> --dry-run      # offline preview: 124 exams, 131 rooms, 27 events …
   # credentials: a service-account key kept OUTSIDE the repo, or `gcloud auth application-default login`
   $env:GOOGLE_APPLICATION_CREDENTIALS="C:\secure\<service-account>.json"
   node seed_firestore.mjs --project <your-project-id> --confirm-live <your-project-id>
   ```
   The script refuses before connecting (covered by `npm run test:seed`) when:
   - it's a live project without `--confirm-live`, or `--confirm-live` names a different project;
   - it's a `demo-*` project id without emulator hosts;
   - emulator hosts point anywhere other than this machine, or are combined with `--confirm-live`;
   - the removed `--admin` flag is used.

   `--emulator-test-users` (which creates the known-password test accounts) is allowed **only** with a `demo-*` project id and **both** `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` set to local emulators (§2a). It is always refused for a live target, even with `--confirm-live`.
8. **Create the first administrator (one time only).** The admin dashboard is **sign-in only**: it can't create accounts. Further admins and content managers are granted from the dashboard (Administrators) once the first admin exists.
   1. Create the admin's sign-in account in **one** of two ways:
      - **Student app** (live build): Create student account → fill in the form → Create account. This creates only the Firebase Authentication account.
      - **Firebase Console** → Authentication → Users → Add user (email + password).
   2. **Verify the email.** Open the verification link sent to the address. A Console-added user can sign in to the student app, which shows "Verify your email" with a **Resend email** button. After verifying, the student app shows "Complete your profile". **Stop there and sign out; don't submit it.** An admin account needs no student profile, and submitting one would create a pending student record and SAP ID claim.
   3. Copy the UID from Console → Authentication → Users.
   4. Choose **one** of these:
      - **Script** (needs Admin SDK credentials as in step 7). It reads the email from Firebase Authentication, refuses unverified or disabled accounts, refuses if any admin or content manager already exists, and writes an audit record:
        ```powershell
        node bootstrap_admin.mjs --project <your-project-id> --uid <UID> --dry-run
        node bootstrap_admin.mjs --project <your-project-id> --uid <UID> --confirm-live <your-project-id>
        ```
      - **Console, no credentials:** Firestore → Start collection `admins` → Document ID = the UID → fields `email` (string, exactly the account's email) and `role` (string, exactly `admin`). Console writes bypass the rules, so double-check the UID and the spelling of `admin`; any document in `admins` grants staff access.
   5. Sign in to the admin dashboard (step 9) with that account and confirm the Administrators page lists it.

   A self-registered user cannot make themselves an admin: no rule lets a non-admin write to `admins`. This is covered by the rules tests.
9. **Run against the project:**
   ```powershell
   cd ..\app
   flutter run --dart-define=CAMPUSSYNC_BACKEND=live
   flutter run -d chrome -t lib/main_admin.dart --web-port 8767 --dart-define=CAMPUSSYNC_BACKEND=live
   ```
   `localhost` is an authorised domain by default, so the admin dashboard works from `flutter run -d chrome`. Tests never use live mode: `flutter test` runs in demo mode; the rules tests and `e2e/` refuse anything but the emulator.
10. **Repeat the checks against the real project:** register → verify the email (a real email arrives) → admin approves → timetable and exams visible; a student is denied the admin dashboard and draft data; offline banner in airplane mode; data persists across two devices and after reinstalling. Record the results in `docs/TEST_CASES.md`.

## 4. Admin dashboard hosting
```bash
cd app
flutter build web -t lib/main_admin.dart --dart-define=CAMPUSSYNC_BACKEND=live
# firebase/firebase.json hosts ../app/build/web
cd ../firebase && firebase deploy --only hosting
```
Add the hosting domain under *Authentication → Settings → Authorised domains*.

## 4b. Release APK (live or demo; choose explicitly)
**A plain `flutter build apk --release` produces a DEMO build:** bundled reference data, a "Demo mode … nothing is saved to a server" notice, no sign-in. The backend is fixed at build time by `--dart-define=CAMPUSSYNC_BACKEND` (`lib/firebase_options.dart`); there is no switch inside the app.

Use the build script, which makes the backend a required choice and checks the finished APK:
```powershell
cd <repo>
# Live: your Firebase project, real sign-in (needs §3 steps 6–8 done first)
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Backend live
# Demo: offline, bundled data (intentional demo builds still work)
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Backend demo
# Which backend was an existing APK built for? (builds nothing)
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Verify app\build\app\outputs\flutter-apk\app-release.apk
```
The script runs `flutter build apk --release --dart-define=CAMPUSSYNC_BACKEND=<backend>`. It then reads the backend the APK records and fails if the build failed, the APK is stale, or the recorded backend differs from the one requested.
- `android/app/build.gradle.kts` resolves the backend from the same dart-define, exactly as the Dart code does. It writes the result into the manifest as `<meta-data android:name="campussync.backend">` (`demo`, `emulator` or `live`) and fails the build on an unknown value.
- APKs built before 2026-10-22 have no such entry; `-Verify` reports them as "not recorded".

The equivalent manual command for a live APK is:
```powershell
cd <repo>\app
flutter build apk --release --dart-define=CAMPUSSYNC_BACKEND=live
```
Output: `app\build\app\outputs\flutter-apk\app-release.apk` (≈64 MB, debug-signed). Install with `adb install -r <path>`. A live APK starts at "Create student account / Sign in" with no "Explore the demo" button. If you see the demo notice, the APK is a demo build.
R8 shrinking is **disabled** (`android/app/build.gradle.kts`) because it broke the shared_preferences JNI bridge at startup (see `android/app/proguard-rules.pro`). If you re-enable it, smoke-test the release APK on a device before distributing.

## 5. Android release build (separate, explicit step)
1. Create an upload keystore (keep it and `key.properties` out of git) and configure `signingConfigs.release` in `app/android/app/build.gradle.kts`.
2. Choose the final application ID before the first store upload. It can't change afterwards.
3. Run `flutter build appbundle --release --dart-define=CAMPUSSYNC_BACKEND=live`. Without the dart-define the bundle is a demo build (§4b).
4. The Play Console needs a privacy policy (the app processes name, email, SAP ID and roll number), a data-safety form, store listing assets and a closed-testing track.

**The app has not been published to the Play Store.**

## 6. Updating reference data
Edit `tools/build_seed.py` (the hand-transcribed source of truth), then run `python -I tools/build_seed.py`. Re-run the app tests. In production, use the admin dashboard (CSV/JSON import, preview, validation, publish): the seed script is create-only and never updates documents that already exist.
