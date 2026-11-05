# CampusSync – Final Release Report

_Audit date: 2026-10-22. Live Firebase project (Spark plan, no billing). Package `com.campussync.campussync`._

Legend: **VERIFIED** = exercised and observed this session · **FAILED** · **NOT VERIFIED** = not exercised (reason given).

## 1. Release artifact
| Item | Value |
|---|---|
| APK | `<repo>\app\build\app\outputs\flutter-apk\app-release.apk` |
| Build | `powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Backend live`: exit 0, built 2026-10-22 19:45:43 |
| Package / version | `com.campussync.campussync` 1.0.0 (versionCode 1), minSdk 24, targetSdk 36 |
| Size | 67,547,085 bytes (64.4 MB) |
| SHA-256 | `fd65b1b7376ded1c1e35d2769900e106c08aec8a8629dd487028e6e443a01771` |
| Backend marker | manifest `campussync.backend=live` (read back from the APK by the build script) |
| Signature | `apksigner verify` passes (v2 scheme). **Signed with the Android debug key** (CN=Android Debug): fine for sideloading and demos, **not a production/Play Store signing setup**. |
| Integrity | `unzip -t`: no errors. No source file is newer than the APK. |

## 2. Implemented features (summary)
- **Student app (Android):**
  - email/password registration with email verification, SAP ID claim and admin approval;
  - division and batch timetable; rooms and floor explorer with availability; exams; academic calendar;
  - announcements (search, filter, save, detail, external link);
  - local reminders; offline cache; settings; virtual campus and library focus timer.
- **Admin dashboard (web, run locally at http://localhost:8767, not published):**
  - timetables (import, validate, publish, roll back); rooms and floors; announcements (draft/publish/archive);
  - exams and calendar; student approval, suspension and SAP ID release; administrators; audit log.

## 3. Firebase configuration: VERIFIED
- `google-services.json` and `firebase_options_live.dart` point to the live project. The release APK selects live mode (marker above). Demo mode can't be reached in a live build: there is no "Explore the demo" button, verified on the emulator.
- Firestore rules and indexes were deployed on 2026-10-21 and haven't changed since; not redeployed. Unauthenticated reads of protected collections return HTTP 403 (verified 2026-10-22).
- Reference data was seeded create-only on 2026-10-22 (362 documents; nothing overwritten):
  - departments 1, programs 1, academicYears 1, groups 4, subjects 8, faculty 10;
  - rooms 131, floors 10, timetableVersions 4 (published), electives 37;
  - exams 124 (published), calendarEvents 27 (published), settings/campus 1.
- Consistency check: **0 problems**. Every timetable room, subject and faculty reference, every exam group/elective link and every room's floor resolves. Timetable entries: Div B 38, Div C 34, OE-I 46, OE-II 44.

## 4. Announcements: VERIFIED (data), NOT VERIFIED (student device view)
| Record | Status | Audience | Review flags | Audit |
|---|---|---|---|---|
| `ann-isl-winter-internship-2026` | published | `all` | cleared | `announcement.published` by admin@example.com |
| `ann-icpc-india-regionals-2026` | published | `all` | cleared | same |
| `ann-qiskit-fall-fest-2026` | published | `all` | cleared | same |

- There are exactly 3 announcements and no duplicate titles. Dates are valid ISO dates; links are https.
- Admin-entered content observations (left unchanged; admin-authored):
  - The Qiskit `source` still reads "Supplied by the project team (details pending)".
  - The ICPC registration link is the ICPC rules page.
  - The ICPC image URL is an SVG, which Android can't render; it's hidden without error.
- **UX fix made in this release:** the detail screen labelled every link "Open registration link", which presented the closed ICPC/Qiskit registrations as open. It now reads **"Open official link"**. The descriptions state the registration status. Ended items show "This announcement has ended." with the link disabled.
  - Files: `app/lib/ui/updates/announcement_detail.dart`; editor helper text in `app/lib/ui/admin/admin_content.dart`.
  - Tests: `app/test/announcement_detail_test.dart` (4 tests: neutral label, ended state, missing optional fields, undecodable image).
- Student retrieval on a device: **NOT VERIFIED.** No approved test-student account exists (see §6). Rules tests cover the published/`all` read path for active students.

## 5. Automated checks (re-run 2026-10-22)
| Command | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **120/120** (116 + 4 new) |
| `npm run test:rules` (throwaway emulator) | **61/61** |
| `node --test test/seed.test.mjs` / `npm run test:seed` | **8/8** / **11/11** |
| `node run_isolated.mjs` (Chrome e2e, dedicated emulator 8180/9180) | Timetable 17/17, Rooms & announcements 18/18, Exams/calendar/access 30/30, Student registration **16/16** = **81/81** |

**Student registration suite:** in the first full run it failed with a 60 s page-load timeout (4/8). Diagnosis: the Android emulator was competing for CPU with three headless Chrome instances, and page loads took between 17 s and more than 45 s. Rerun alone with the Android emulator paused, it passed **16/16**. No code or test was changed for that rerun.

## 6. End-to-end on the live backend
| Workflow | Result |
|---|---|
| Release APK installs and launches on the Pixel_9 emulator (Android 37 beta) | **VERIFIED** (cold start 11.8 s just after resume; no crash in logcat) |
| Live registration screen loads Div B / Div C from the live project | **VERIFIED** (screenshot `i1`) |
| Offline registration shows a network error; empty catalogue shows the setup message | **VERIFIED** earlier today (`h1`, `h2`) |
| Admin account bootstrap (`admin@example.com`, role `admin`, audited) | **VERIFIED** |
| Admin dashboard sign-in, student approval, publishing 3 announcements | **VERIFIED via live data**: audit records `student.active` and `announcement.published` written by the admin through the rules-checked dashboard |
| Student sign-in, session persistence, profile/group, timetable, rooms, exams, calendar, announcements, sign-out (as a student) | **NOT VERIFIED**: `student@example.edu` has no Firebase account yet |
| Student blocked from admin screens/operations | **NOT VERIFIED on live** (needs a student account). Covered by rules tests and e2e AC checks. |

## 7. Security and configuration audit
- No private keys, service-account files, keystores or `.env` files in the project. ADC credentials live in `%APPDATA%\gcloud`, outside the repo. The emulator test passwords exist only in emulator-gated scripts and tests, which refuse live targets.
- Rules allow unauthenticated reads only for the registration catalogue (groups, departments, programs, academicYears). Everything else needs a signed-in, active student or staff. Deletes of announcements are refused. Writes need staff and an audit record.
- Cleartext HTTP is allowed only in the debug manifest. Release permissions:
  - INTERNET, ACCESS_NETWORK_STATE;
  - POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, WAKE_LOCK, VIBRATE (reminders);
  - **C2DM RECEIVE and READ_GSERVICES**, which come from the unused `firebase_messaging` dependency (FCM isn't implemented). Recommended follow-up: remove `firebase_messaging` from `pubspec.yaml`. It wasn't changed during this release audit.
- No `print`/`debugPrint` logging in `app/lib`.

## 8. Known limitations and manual steps
1. **Student E2E pending:** register `student@example.edu`, verify, submit the profile, and approve it in the dashboard; then repeat §6 as that student.
2. **Admin account also has an approved student profile** (Div B, holding SAP ID …29). That was an accidental submission, later approved. It doesn't affect admin rights. To free the SAP ID for the real student account: dashboard → Students → that entry → **Suspend**, then **Release SAP ID**.
3. Announcement content tidy-ups (optional, admin): Qiskit source text; ICPC link and image.
4. Deadline reminders use `endDate` and say "Deadline tomorrow" even when the end date is an event's last day.
5. FCM push notifications aren't implemented (they would need Cloud Functions/Blaze). Reminders are local only.
6. The admin dashboard is local only (not hosted).
7. Release signing uses the debug key.
8. The physical-phone checklist (`docs/PHYSICAL_DEVICE_CHECKLIST.md`) hasn't been run against this build.
