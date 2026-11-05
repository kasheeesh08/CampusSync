# Firebase backend security audit: findings register

Source: the read-only audit run before the first production connection (2026-10-21), with 16 probe tests on a local emulator. This file records the audit's finding IDs so they aren't lost between sessions. Status is checked against the current code; line numbers refer to `firebase/firestore.rules` unless stated otherwise.

## Fixed (each covered by tests; see `docs/TEST_CASES.md`)
| ID | Finding | Fix / evidence |
|---|---|---|
| H1 | SAP ID squatting: any signed-in user (even unverified) could claim unlimited SAP IDs, with no profile and no way to release them | Claims need a verified email and the claimant's first profile in the same write; admin "Release SAP ID". Rules tests "SAP ID claims (H1)" |
| H2 | Spoofable student identity: profile creation accepted any fields; the admin approval screen showed a self-written email; email verification was checked only in the app | Field allowlist + validation; `email` must equal the verified token email; approval screen labels verified vs self-declared. Rules tests "Student identity fields (H2)" |
| H3 | Students saw no calendar events in Firestore modes: seeded events had no `status` | Seed has explicit `status`; missing/unknown → draft. Rules tests "(H3)", logic tests |
| H4 | Unsafe seed script: seeded draft announcements, overwrote admin edits, `--admin` bundled with seeding | Create-only seed, `--confirm-live`, separate `bootstrap_admin.mjs`. `firebase/test/seed.test.mjs` |
| F1 | A release from a stale card could delete another (suspended) student's SAP claim | Rules bind the delete to the claim's own holder via the `sapReleased` transition. Rules test "REGRESSION (audit probe B)" |
| F2 | "Release SAP ID" stayed visible after a release; repeating it showed an error | Button hidden for released accounts; repeat reported as "already released". `admin_students_test.dart` |
| M1 | Android emulator mode failed at startup (`[core/duplicate-app]`): Android auto-initialised the live app from `google-services.json` | `FirebaseInitProvider` removed in `android/app/src/main/AndroidManifest.xml`; verified on the Pixel_9 AVD in demo, emulator and live (offline) modes (TEST_CASES "M1") |
| M2 | Students could read every published announcement and exam, including those targeted at other groups; targeting was applied only in the app | `announcements`/`exams` carry denormalised `audienceKeys` (`all`, `group:<id>`, `dept:<id>`, `oe:<id>`). Rules `forThisStudent()`/`studentAudience()` allow a read only if a key matches the student's group, department or chosen electives; the app queries `audienceKeys array-contains-any` with exactly those keys. Rules tests "Audience enforcement (M2)"; `audience_test.dart` (server filter == `Exam.appliesTo`); E2E EX-12 (Div B student: 5 visible, 119 hidden) |
| M3 | Announcements were validated only for title and status (a `javascript:` link or a 200 KB description was accepted) | `validAnnouncement()`: field allowlist, `id` = document id, category list, length limits (summary 200, description 5000, source 300, URLs 2048), http(s)-only URLs without spaces, ISO dates, audience shape and `audienceKeys` consistent with it. The admin form now has the same description/source limits. Rules tests "Announcement validation (M3)" |
| L1 | Admins could overwrite published timetable versions in place | A published or archived version is frozen: only `status`/`publishedBy`/`publishedAt`/`updatedAt`/`updatedBy`/`auditId` may change, and never back to `draft`. `publishVersion` updates only those fields for non-draft versions. Rules tests "Timetable version immutability (L1)"; E2E timetable suite (publish, rollback) 17/17 |
| L3 | Any document in `admins` granted staff access, even with a missing or mistyped role | `isStaff()` requires `role` to be `admin` or `contentManager`. The admin list shows such accounts as "invalid role (no access)" instead of as content managers. Rules tests "Admin role values (L3)" |

## Partly fixed
| ID | Finding (as audited) | What is fixed | What remains |
|---|---|---|---|
| M4 | Staff writes succeeded without an audit record, and `actorEmail` could be forged | Every app write path (catalogue, settings, rooms, floors, timetables, announcements, exams, calendar, student approval/suspension, SAP ID release, role grants) must name, in `auditId`, a **new** audit record created in the same commit by the same user (`audited()`). The audit rule requires `actorEmail` to equal the signed-in token email. Rules tests "Audit enforcement (M4)"; all E2E admin workflows pass with the requirement | **Deletes** (exams, calendar events, role revocation) carry no data, so they can't name an audit record: the app still writes one, but the rules don't require it. Collections written only by the Admin-SDK seed (`subjects`, `faculty`, `electives`, `importJobs`) are not covered. Console edits bypass all rules |
| L2 | Admins could remove each other, including the first admin, with no last-admin protection | No rule change needed for sequential changes, now proven by tests: an admin can't remove or demote themselves, and once A removes or demotes B, B is no longer an admin, so B's attempt against A is denied. Sequential removal therefore always leaves at least one admin. Rules tests "Administrator removal (L2)" | Two admins removing each other at the same instant was not tested (the emulator can't reproduce truly concurrent commits). Recovery is through the Console |

## Open (not fixed)
| ID | Finding (as audited) | Current status |
|---|---|---|
| M5 | Anyone signed in could test whether a SAP ID is already registered (unclaimed IDs are readable, claimed ones denied). | **Reduced.** Since H1, only accounts with a verified email can probe (`sapIndex` get rule, line 208). The registration duplicate check depends on it. |
| L4 | The app takes the document ID from an `id` field if present; a mismatch would make edits write to a different document. | **Open** (`app/lib/data/firestore_repository.dart` line 26; announcements now also require `id` = document id in the rules, M3). |
| L5 | Database delete protection is off (free to enable); point-in-time recovery is a paid feature and stays off. | **Open, console setting**, last observed during the read-only check on 2026-10-21. Not re-checked, to avoid accessing production. |

Registration error message (not a finding ID): **fixed**. `registerProfile` now tells apart:
- duplicate SAP ID: a server-side claim check, then a re-check if the write is denied, so a lost race is still reported as a duplicate;
- rejected details;
- unverified email: refused in the app before any lookup;
- network failure;
- unexpected errors, which report only the code, never raw rule text.

It reads codes from `FirebaseException` and from web-wrapped `[cloud_firestore/<code>]` text. Evidence: `registration_errors_test.dart`, `registration_form_test.dart`, and E2E RG-06 and RG-12 to RG-14. In the browser, an offline submit is caught first by the sign-in token refresh ("No internet connection…"). The Firestore-level network message is covered by unit tests only.
