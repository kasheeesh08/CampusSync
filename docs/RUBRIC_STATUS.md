# Rubric and correction-criteria status (honest self-assessment)

Status as of 2026-10-20, after milestone 4 (release APK). Statuses:
- **Pass:** evidence in the repo.
- **Pending:** needs a phone, external configuration or missing information.
- **Fail:** tested and did not pass.
- **Needs review:** evidence exists but doesn't fully establish the criterion.

Marks are awarded by the examiner; this file only maps criteria to evidence.

## Correction criteria
| # | Criterion | Status | Evidence | Remaining action / verification needed |
|---|---|---|---|---|
| 1 | UI/UX design (attractive, light theme, consistent, responsive) | **Pass** | Material 3 light theme; real screenshots of every screen (`30`–`38`, `52`, `78`–`91`, `b0`–`d0`, `e0`–`e8`); admin web screens `90`–`a4`; narrow-screen and large-text overflows fixed | Confirm layout on the physical phone (checklist rows 11, 15) |
| 2 | Coding standards and best practices | **Pass** | Layered structure (`docs/ARCHITECTURE.md`, `docs/CODE_WALKTHROUGH.md`); `flutter analyze`: no issues; error-handling table in ARCHITECTURE | — |
| 3 | Input hints, labels, placeholders | **Pass** | Hints/labels on every field, `*` on required fields, numeric/email keyboards; `83`–`85_device_validation_*` | — |
| 4 | Input validation | **Pass** | `domain/validators.dart`; `registration_form_test.dart` (6 tests); Chrome checks AN-01..03, EX-01/02/06/07, RM-02/03, TT-03..06; refused records confirmed absent from Firestore | — |
| 5 | ≥5 positive + ≥5 negative test cases with actual results | **Pass** | `docs/TEST_CASES.md`: M2 (10 P / 11 N), M3 (11 P / 6 N), M4 (5 P / 1 N), each with data, steps, expected, actual, status and evidence; 107 unit/widget + 61 rules + 9 seed-safety + 81 Chrome checks passing on the current code (Chrome suites against a dedicated temporary emulator) (`docs/evidence/`) | Notification delivery: a real defect was found (the app cancelled its own delivered notice) and fixed; the re-test was interrupted (emulator stopped for low memory), so it stays **not verified** |
| 6a | Runs on an Android emulator | **Pass** | Pixel_9 AVD throughout; **release APK** clean-installed and smoke-tested (M4); after M1 fix: debug builds start in demo, emulator (signed in against a dedicated emulator, `g2_*`) and live (offline start only) modes | Release APK not rebuilt since the manifest change |
| 6b | Installed and tested on a physical phone | **Pending** | Checklist ready: `docs/PHYSICAL_DEVICE_CHECKLIST.md` | User runs the checklist on a real phone; adds `phone_*.png` and results |
| 7 | Documentation quality | **Needs review** | Report follows the template (ch. 1–4, 7, 8); architecture, deployment, test cases, data notes, code walkthrough | Fill the front page (subject code, division, full names, guide); add phone results to §7.3; convert to DOCX/PDF (no converter installed) |
| 8 | Final verification | **Pending** | Everything verifiable here is verified | Depends on 6b and the report details |
| 9 | Strict adherence to rubrics | **Needs review** | This matrix | Becomes Pass once 6b and 7 are closed |

## Project rubric (40 marks): evidence map
| Criterion | Evidence | Open items |
|---|---|---|
| Problem originality and user needs (5) | Report ch. 1–2; real MPSTME documents (timetables, exam PDF, calendar, floor plans) | — |
| Self-learning / new concepts (5) | Report §8.2 (9 concepts): rules-tested Firebase security, emulator-based E2E, interactive 2.5D campus over real floor plans, restart-safe focus timer, timezone-aware notifications, versioned publish/rollback with audit, automated Chrome checks | — |
| Standardised workable app (10) | Release APK builds and runs; Material design; validated data | Debug-signed, R8 disabled, no Play Store listing; real Firebase project configured in the app but live connectivity not yet verified (DEPLOYMENT §3, §5) |
| Individual contribution (10) | Can't be shown by the code | Team documents who did what |
| Viva / demo (10) | Integrated modules; `docs/CODE_WALKTHROUGH.md`; reproducible demo (APK; DEPLOYMENT §2a/2b) | Physical-phone demo |

## Is a real Firebase project required for the demo?
**No, not for the student app.** The release APK runs fully in demo mode with the official data: timetable, rooms, exams, calendar, virtual campus, focus sessions and reminders. Accounts, admin approval, publishing and security rules are implemented and verified against the **local Firebase emulator** (screenshots `60`–`99`, `a0`–`a4`), which can be shown live from the development PC (DEPLOYMENT §2a/2b). A real project is only needed to demonstrate live sign-in on a phone or sync across devices (steps in DEPLOYMENT §3).

## Known limitations (also in the report §7.4)
- Security audit (`docs/SECURITY_AUDIT.md`): M2, M3, L1 and L3 are fixed with regression tests. M4 and L2 are partly fixed (audit binding isn't possible for deletes; concurrent mutual admin removal is untested). M5, L4 and L5 are still open.
- Chrome E2E logs show non-fatal Flutter engine keyboard errors when synthetic keystrokes type `/ - * +` (TEST_CASES "Re-verification"); whether real keyboards trigger them is unverified.
- Focus sessions are device-local; the desk layout is illustrative; only the Academic Block has an interior.
- Focus-completion notification: defect fixed (`cancelAllPendingNotifications`); delivery re-test interrupted and **not verified** (TEST_CASES M4 #3).
- No FCM push; the real Firebase project is configured but live connectivity is not verified; the release is debug-signed and R8 shrinking is disabled.
