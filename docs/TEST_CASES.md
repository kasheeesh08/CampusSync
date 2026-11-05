# CampusSync – Test Cases and Results

All automated tests run with `flutter test` in `app/`.
**Last run: 2026-10-20, Flutter 3.47.7 / Dart 3.13.5. Result: 46 tests, 46 passed, 0 failed.**
Manual cases were run on the Android emulator (AVD *Pixel_9*, Android 17 / API 37 beta image).
Screenshots are in `docs/screenshots/`.

## Rubric test cases (5+ positive, 5+ negative)

| ID | Type | Scenario | Input data | Expected result | Actual result | Status |
|---|---|---|---|---|---|---|
| TC-P01 | Positive | Valid registration fields | Email `student@example.edu`, password `campus2026`, SAP ID `99999300123`, roll `B001` (Div B), name `Test D'Souza` | All validators accept | All returned no error (`logic_test: Input validation (positive)`) | Pass |
| TC-P02 | Positive | Division-specific timetable | Div B and Div C published versions, Monday 20 Jul 2026, 08:00 | Div B shows SE/IVP labs; Div C shows MAD (CR-407); neither substitutes the other | Div B = {SE, IVP}, Div C = {MAD} (`domain_test`) | Pass |
| TC-P03 | Positive | Occupied room detection | CR-402, Mon 20 Jul 2026, 10:00–11:00 | Occupied by Div B Software Engineering | Status `occupied`, conflict SE / Div B | Pass |
| TC-P04 | Positive | Batch-specific schedule | Div B batch B1 vs B2, Monday 08:00 | B1 → SE lab CL-401, B2 → IVP lab CL-503 | As expected | Pass |
| TC-P05 | Positive | Valid CSV timetable import | `Mon,08:00,10:00,lab,SE,PRK,E. CL 401,X1` and `Tue,…,BC Lab` | Parsed; room aliases and faculty initials resolved | `CL-401`, `fac-prashasti-kanikar`, `LAB-BASIC-COMMUNICATION-LAB` | Pass |
| TC-P06 | Positive | Publish and rollback | Draft v2 without OR → publish → re-publish archived v1 | Draft hidden until published; v2 live; rollback restores v1; audit entries written | As expected (`Demo repository admin workflow`) | Pass |
| TC-P07 | Positive | New group affects availability | Add *IT Sem V Div A* and publish an entry in CR-301, Mon 10–11 | CR-301 changes from "no known class" to "occupied" with no code change | As expected | Pass |
| TC-P08 | Positive | Demo onboarding (widget) | Name `Tester`, Div B, batch B1 | Campus home opens with the greeting | Profile saved, home shown (`widget_test`) | Pass |
| TC-P09 | Positive | Next class | Div B B1, Mon 20 Jul 2026 12:10 | Skips break and library, returns AI at 14:00 | AI, not in progress | Pass |
| TC-P10 | Positive | Reminder planning | Div B B1, Mon 09:00, lead 10 min | First reminder 09:50 (SE at 10:00); stable keys on re-plan | As expected | Pass |
| TC-N01 | Negative | Empty or malformed email | `""`, `student@`, `student.nmims.edu` | "Email is required." / "Enter a valid email…" | Messages shown as expected | Pass |
| TC-N02 | Negative | Weak or mismatched password | `short1`, `onlyletters`, confirmation mismatch | Rejected with specific messages | As expected | Pass |
| TC-N03 | Negative | SAP ID boundaries | 7 digits, 13 digits, `7002A300123` (8 and 12 digits accepted) | Rejected (length / digits only) | As expected | Pass |
| TC-N04 | Negative | Roll number format / division mismatch | `B01`; `C001` for Division B | Rejected | As expected | Pass |
| TC-N05 | Negative | Unsafe links, reversed dates, long title | `javascript:alert(1)`, `ftp://…`, end < start, 141-char title | Rejected | As expected | Pass |
| TC-N06 | Negative | Malformed CSV rows | Invalid weekday, end < start, `25:00`, unknown room `CR 999` and faculty `XYZ` | No entries imported; 4 line-level errors | 0 entries, 4 errors | Pass |
| TC-N07 | Negative | CSV missing columns | Header `day,from,to` | "Missing column(s)…" | As expected | Pass |
| TC-N08 | Negative | Invalid timetable cannot be published | Double-booked CR-402, unknown room `CR-999`, unknown subject | `canPublish == false` with errors listed | As expected | Pass |
| TC-N09 | Negative | Room not confirmed free under partial coverage | CR-402 Mon 12–13 (no class in B/C) | `noKnownClass`, not `freeVerified` | As expected | Pass |
| TC-N10 | Negative | Missing / inactive / non-bookable room | `NOPE`, inactive room, library | `unknownRoom` / `unavailable` | As expected | Pass |
| TC-N11 | Negative | Duplicate SAP ID; self role change | Second account with the same SAP ID; admin revoking own role | `RepositoryException` | As expected | Pass |
| TC-N12 | Negative | Unpublished group gets no substituted timetable | Profile with unknown group id | Day view = "no timetable" | As expected | Pass |
| TC-N13 | Negative | Empty demo onboarding form (widget) | Tap *Enter campus* with no name | "Name is required." | Shown | Pass |

## Additional automated coverage
Boundary times (class ending 11:00 doesn't block 11:00–12:00; 10:59 does), overlapping labs and lectures of different lengths, cancelled entries, draft vs published vs highest version, dates outside the effective range, invalid intervals, OE-I offering replacing the generic elective slot, free periods vs empty source slots, validator acceptance of all seeded timetables with zero errors, source overlaps reported as warnings, Floor 2 having no fabricated rooms, announcements kept as drafts, publish planning for overlapping and non-overlapping ranges, version numbering, exam and deadline reminder timing, `parseHm` boundaries, announcement timing states.

## Manual emulator verification (Pixel_9 AVD)
| ID | Check | Result |
|---|---|---|
| EM-01 | Debug APK installs and launches (`01_welcome.png`) | Pass |
| EM-02 | Empty form validation (`03_validation.png`) | Pass |
| EM-03 | Profile setup → campus home with correct next class (Wed 08:00 MAD, CC 702) (`05_campus_home.png`) | Pass |
| EM-04 | Day and week timetable match the Div B PDF (`06`, `07`) | Pass |
| EM-05 | Floor 4 explorer: DE Lab occupied by OE-I lab Tue 5–6 pm, other rooms "unverified" (`08`, `09`) | Pass |
| EM-06 | Updates: announcements empty state explains drafts; calendar and exams tabs (`10`, `12`, `13`) | Pass |
| EM-07 | Notification permission prompt (Android 13+), 19 reminders scheduled, alarms visible in `dumpsys alarm` (`14`, `15`) | Pass |
| EM-08 | Admin dashboard (web build, headless Chrome) overview and timetable health (`20_admin_overview.png`) | Pass |
| EM-09 | Issue found: stale "Name is required" message after typing (`04_profile_filled.png`) | Fixed (live validation); tests re-run |

## Pending (not executed, so not claimed)
- **Physical Android phone:** not connected in this environment. Install `app-debug.apk` (or `flutter run`) on a phone and record results here.
- **Firebase-backed flows** (registration, email verification, admin approval, Firestore rules) need a Firebase project. Test the rules with the Firebase emulator (`firebase emulators:start`) after configuration.

---
## Backend & data milestone (2026-10-20, evening)

**Automated results:** `flutter test`: 60/60 passed. `npm run test:rules` (Firestore emulator): 18/18 passed. `flutter analyze`: no issues.

### New automated cases
| ID | Type | Scenario | Expected | Actual | Status |
|---|---|---|---|---|---|
| TC-P11 | Positive | Exam import counts/provenance | 124 records (88 stream rows + 36 OE), each with file + page | As expected | Pass |
| TC-P12 | Positive | Computer Engineering exams map to Div B **and** C | OR 17/11, AI 19/11, SE 23/11, OS 25/11, IVP 27/11, 10:00–13:00 page default | As expected | Pass |
| TC-P13 | Positive | Cell time overrides page default | Data Wrangling 14:00–17:00, Business Strategy 10:00–12:00 | As expected | Pass |
| TC-P14 | Positive | Student sees group exams + chosen electives only | Div C: 5 core; adding 5G + Quantum adds 2 | As expected | Pass |
| TC-P15 | Positive | Floor 2 integrated without duplicate IDs | 13 rooms, IDs unique, CR-201 "no known class" | As expected | Pass |
| TC-P16 | Positive | Persisted sign-in loads data on cold start (regression) | data fetched without manual refresh | Pass with fix; **fails without fix** (verified) | Pass |
| TC-N14 | Negative | Duplicate exam (same subject/date/students) | Error | As expected | Pass |
| TC-N15 | Negative | Overlapping exams for the same group | Clash error; different groups or 14:00 slot fine | As expected | Pass |
| TC-N16 | Negative | Bad times / unknown group / out-of-window date / "9am" | Errors + window warning | As expected | Pass |
| TC-N17 | Negative | Draft or withdrawn exam visibility | Not returned to students; republish restores | As expected | Pass |
| TC-N18 | Negative | No exam invented for MAD | MAD absent | As expected | Pass |
| TC-N19 | Negative | Pending account fetches academic data | No fetch; stage pending | As expected | Pass |

### Security rules (Firestore emulator, `firebase/test/rules.test.mjs`)
- **Allowed:** public group catalogue; active student reads published timetables and exams via filtered queries; registration (pending profile + SAP claim in one transaction); student edits cosmetic fields; admin approves a student and publishes an exam with an audit record; content manager publishes an announcement; admin grants another user a role.
- **Denied:** anonymous reads of rooms, exams and students; pending student reads; active student reading drafts or querying without a status filter; self-approval, self group change, self-registering as active; claiming an existing SAP ID; reading another student; listing the SAP index; self-granting admin; student writes to exams or timetables; content manager writing timetables, rooms or roles; admin changing their own role; forged `updatedBy` or invalid status; audit update, delete or forgery.

### Live-mode end-to-end run (Pixel_9 AVD + Firebase Local Emulator Suite, project `demo-campussync`)
| Step | Result | Evidence |
|---|---|---|
| Registration form loads divisions from Firestore while signed out | Pass | `61`–`65_live_register_*.png` |
| Account created; Firestore holds `pending`, `groupId=null`, SAP claim | Pass | `66_live_verify_email.png`; Firestore query |
| Email verification (emulator link) → pending-approval gate | Pass | `67_live_pending_approval.png` |
| Student account opens admin dashboard → Access denied | Pass | `68_live_admin_denied_for_student.png` |
| Admin approves with Div B → Firestore `active` + audit `student.active` | Pass | `71`–`73_live_admin_*.png`; Firestore query |
| Admin withdraws CE Operating Systems exam → only that record `archived`, audit `exam.save` | Pass | `76`, `77_live_admin_*.png`; Firestore query |
| Student signs in → Div B home; exams show OR, AI, SE, IVP (OS hidden) | Pass | `78_live_student_home.png`, `79_live_student_exams_after_withdraw.png` |
| Student picks OE-I 5G → `oe1OfferingId` persisted; 5G exam (2 Dec 10–13) appears | Pass | `80_live_student_exams_with_elective.png`; Firestore query |
| Floor 2 in the room explorer, all rooms "No class listed (unverified)" | Pass | `81_live_rooms_floor2.png` |
| Backend stopped → offline banner, cached data still readable | Pass | `82_live_offline.png` |
| Night palette on screen (after 19:00) | Pass | `78_live_student_home.png` |

The admin steps ran the real admin dashboard code on the Android emulator (same Dart code as the web build) because adb can drive it. The web build itself was only render-checked.

---
## Milestone 2: gap closure and rubric evidence (2026-10-20, night)

**Executed results (logs in `docs/evidence/`):**
| Suite | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` (in `app/`) | No issues (`flutter_analyze.txt`) |
| Unit + widget tests | `flutter test` | **70/70 passed** (`flutter_test.txt`) |
| Firestore security rules | `node --test test/rules.test.mjs` against the Firestore emulator | **18/18 passed** (`firestore_rules_test.txt`) |
| Admin web dashboard in Chrome (real web build, emulator backend) | `node e2e/run_all.mjs` | **62/62 checks, 3/3 suites** (`e2e_chrome_run.txt`) |
| Student app on the Pixel_9 AVD | manual (adb) + `tools/reminders_check.py` | see the device rows below |

The Chrome log omits one repeated browser message, `Cannot read properties of null (reading 'toString')`. It comes from Flutter's web engine (`KeyboardConverter._handleEvent`) reacting to puppeteer's synthetic Ctrl+A/Backspace key events, not from app code, and it never affected a check.

### Formal test cases (rubric format)
| ID | Type | Requirement | Preconditions / test data | Steps | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|---|---|---|
| M2-P01 | Positive | Timetable import + publish | Admin signed in (web); `test_valid_timetable.csv` (4 rows) | Timetables → New version → Import → Choose file → Apply → Save draft → Publish → confirm | 4 entries mapped (room CR 201, faculty name, batch); Div B student sees v2; provenance = file name | As expected | Pass | TT-07..13, `93`/`94_web_tt_*` |
| M2-P02 | Positive | Rollback | v2 published, v1 archived | Roll back to this (v1) → confirm | Student sees v1 again (38 source entries) | As expected | Pass | TT-16, `95_web_tt_rolled_back` |
| M2-P03 | Positive | Room management | — | New room `TEST-ROOM-901`, Floor 2, capacity 40 → Save; Edit → inactive + note → reload | Persisted on Floor 2; edit kept after reload; 2 audit entries | As expected | Pass | RM-04..07, `97_web_room_edited` |
| M2-P04 | Positive | Announcement lifecycle | — | New TEST announcement with valid URL and dates → Save draft → Publish → Archive | Draft hidden; published visible; archived hidden; URL and dates exact | As expected | Pass | AN-04..08, `99_web_announcement_published` |
| M2-P05 | Positive | Exam edit keeps provenance | Imported CE OS exam and 5G elective exam | Edit → Save (each) | officialCode, stream, source, timeSource, status, group or elective links and specific name unchanged | As expected (after fix) | Pass | EX-03, EX-04, EX-04b |
| M2-P06 | Positive | Draft → publish → withdraw exam | — | + Exam (MAD, 30 Nov, 14:00–17:00, source "QA TEST…") → Save → Publish → Withdraw | Saved as draft (hidden) → visible → hidden but kept | As expected | Pass | EX-08..11 |
| M2-P07 | Positive | Student approval + audit | `test.pending@…` pending | Students → Approve → Div B | status active, group Div B, student can now read exams; audit `student.active` | As expected | Pass | AC-07..10, `a3_web_audit_log` |
| M2-P08 | Positive | Group change propagates | TEST student in Div B (device) | Admin sets group Div C (rule-checked API) → student pulls to refresh | Header, next class, timetable switch to Div C; reminders recomputed (19 → 23 class) | As expected (after fix) | Pass | `88_device_after_group_change_divC`, reminders log |
| M2-P09 | Positive | Elective change updates exams + reminders | OE-I not chosen (device) | Me → OE-I → 5G for Everyone | Exam list and reminders add "5G for Everyone" (1 Dec 18:00, starts 10:00) | As expected (after fix) | Pass | reminders log, `87_device_elective_chosen_settings` |
| M2-P10 | Positive | No duplicate reminders | 24 reminders scheduled (device) | Cold-restart the app twice | Still 24, 0 duplicate IDs, timezone Asia/Kolkata | As expected | Pass | reminders log |
| M2-N01 | Negative | Registration validation | Empty profile form on device | Type `7002A` in SAP ID only | Only SAP ID shows "digits only"; untouched fields clean | As expected (after fix) | Pass | `83_device_validation_untouched_fields`, widget test |
| M2-N02 | Negative | Submission blocked | Partially filled form | Tap Submit | Field-specific errors; nothing sent to backend | As expected | Pass | `85_device_validation_submit_blocked`, widget test |
| M2-N03 | Negative | Unsupported file | — | Upload `test_unsupported.pdf` | "Unsupported file type…", nothing applied | As expected | Pass | TT-03, `90_web_tt_unsupported_file` |
| M2-N04 | Negative | Malformed CSV | — | Upload `test_malformed_timetable.csv` | 0 entries, line-level errors, Apply disabled | As expected | Pass | TT-04, `91_web_tt_malformed_csv` |
| M2-N05 | Negative | Conflicting timetable | — | Upload `test_conflicting_timetable.csv` → Apply | "double-booked" error; Publish disabled | As expected | Pass | TT-06, `92_web_tt_conflict_blocked` |
| M2-N06 | Negative | Duplicate room ID | CR-201 exists (Floor 2) | New room `CR-201` | "Room already exists" | As expected | Pass | RM-02, `96_web_room_duplicate_rejected` |
| M2-N07 | Negative | Duplicate / clashing exam | Imported OR exam 17 Nov 10–13 | + Exam OR 17 Nov (duplicate); MAD 17 Nov 11–12 (clash) | Both refused, nothing written | As expected (after fix) | Pass | EX-06/06b/07/07b, `a1_web_exam_duplicate_refused` |
| M2-N08 | Negative | Bad URL / dates / times | — | URL `not-a-link`; end < start; time `9am`; end 09:00 < start 10:00 | Each rejected with a specific message | As expected | Pass | AN-02/03, EX-01/02, CA-01 |
| M2-N09 | Negative | Unauthorised writes (rules) | Student and content-manager ID tokens | Direct REST writes to admins, exams, rooms, timetables; self-approval; audit read | HTTP 403 for every attempt | As expected | Pass | AC-01..06, AC-12, RM-08, AN-06/09 |
| M2-N10 | Negative | Drafts never leak | Draft timetable/exam/announcement | Student queries | Not returned; direct draft reads denied (403) | As expected | Pass | TT-10/11, EX-09, AN-05/06 |
| M2-N11 | Negative | Permission denied | Notification permission revoked (device) | Toggle class reminders on → Don't allow | Switch stays off; clear message; class reminders cancelled; Settings says reminders won't appear | As expected (after fix) | Pass | `90_device_permission_denied_message`, `91_device_notifications_blocked_notice` |

### Defects found this milestone (all fixed, with regression coverage)
| # | Defect | Found by | Fix | Regression |
|---|---|---|---|---|
| 1 | Untouched registration fields showed errors after the first interaction | known issue / device | Field-level `autovalidateMode` on all 8 forms; `*` on required labels | `registration_form_test.dart` (6 tests; proven to fail on the old code) |
| 2 | Web (emulator mode): a reload restored the session against the **production** Auth endpoint, and the next sign-in also went to production | Chrome run (HTTP 400 from identitytoolkit.googleapis.com) | Emulator mode on web uses in-memory auth persistence | Chrome reload check TT-15 |
| 3 | Timetable provenance kept the first uploaded file's name after a later file replaced the entries | TT-13 | Auto-generated source updates; a typed source is kept | TT-13 |
| 4 | A new exam duplicating or clashing with an imported exam **was saved** (error attributed to the other record; duplicates compared official codes only) | EX-06/07 | Pairwise errors reported on both records; local or official code match | `exam_test.dart` regression (proven to fail on old code), EX-06b/07b |
| 5 | Validation messages in admin dialogs appeared as snackbars behind the modal barrier | CA-01 | Inline dialog errors | CA-01 |
| 6 | Editing an elective exam renamed it to the generic "Open Elective I" | device reminder title | Keep the record's name unless the subject changes | EX-04b |
| 7 | Admin group reassignment or suspension applied only after re-login; a stale lab batch carried over | device | Profile reloaded on refresh; a suspended refresh cancels reminders and skips the fetch; foreign batch ignored | `session_test.dart` (2 new tests), `88_device_after_group_change_divC` |
| 8 | Settings claimed reminders were scheduled while Android notifications were blocked | device | Checks `areNotificationsEnabled` and states that reminders won't appear | `91_device_notifications_blocked_notice` |
| 9 | Tappable cards weren't announced as buttons to screen readers | Chrome accessibility tree | `Semantics(button: true)` in shared `SectionCard` | used by the Chrome suites |
| 10 | Profile-completion screen had no sign-out, so a user could be stuck | device | Sign-out action when an account exists | code + analyzer only (screen not reproducible on demand) |
| 11 | Documented `python -I tools/build_seed.py` failed (isolated-mode import) | rerun check | Builder adds its own folder to `sys.path` | rerun produced byte-identical data |

### Data validation (Section 5)
- 124 exam records, each with a `source` naming the PDF, page and column. The 5 CE exams are correct against pages 19–20: OR 17 Nov, AI 19 Nov, SE 23 Nov, OS 25 Nov, IVP 27 Nov, all 10:00–13:00 (page default).
- Students see only their group's linked records plus their chosen electives (client logic, unit-tested and seen on the device). Other-stream records are readable by any approved student through the rules but appear in no student view, because they link to no group. Exam data isn't personal data.
- Review items unchanged: no MAD exam in the source; no Data Analytics exam; the Wireless spelling alias is flagged (EX-05).
- Floor 2: 13 rooms, no duplicate IDs (unit test + RM-01/RM-02).
- Idempotency: rerunning the builder gives byte-identical output for all 7 data files, and re-seeding Firestore leaves counts unchanged (deterministic document IDs).
- Known behaviour: after a group change, a lab batch from the old division is ignored, so both labs of the new division show (and are reminded) until the student selects a batch in Me → Lab batch.

---
## Milestone 3: interactive virtual campus prototype (2026-10-20, ~21:40)

**Automated:** `flutter analyze` no issues · `flutter test` **84/84** (14 new: `focus_test.dart` 13, `world_journey_test.dart` 1).

### New test cases
| ID | Type | Requirement | Data / steps | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|---|---|
| M3-P01 | Positive | Campus → building interior | Tap the "Academic Block" signpost | Character walks to the door; zoom transition into the interior on the Ground floor | As expected | Pass | widget test; `b1`, `b2_world_*` |
| M3-P02 | Positive | Floor navigation (real plans) | Lift panel → 4 | Floor 4 plan, real room statuses (DE Lab occupied Tue 4–6 pm) | As expected | Pass | `b3_world_floor4` |
| M3-P03 | Positive | Room selection | Tap CR 402 | Character walks to the room, room highlighted, real status sheet ("No class listed · unverified", Tue OS 2–3 pm) | As expected | Pass | widget test; `b4`, `b5_world_*` |
| M3-P04 | Positive | Enter the study space | Floor 7 → tap Library region → Enter library (also via the "Library · 7F" campus signpost) | Library study hall with "illustrative layout" notice | As expected | Pass | widget test; `b6`–`b8_world_*` |
| M3-P05 | Positive | Choose a spot, place the avatar | Tap Desk 7 | Character walks to the desk and sits; "Seated at Desk 7" | As expected | Pass | widget test; `b9_world_seated_at_desk` |
| M3-P06 | Positive | Start focus session | 15 min → Start | Countdown from 15:00; completion reminder scheduled at the exact end second | 14:56 shown; reminder 21:52:18 (after fix) | Pass | `c0_world_focus_running`, reminders log |
| M3-P07 | Positive | Pause / resume | Pause → wait 40 s → Resume | Time frozen while paused; reminder withdrawn while paused, rescheduled on resume | 12:56 held for 40 s; 0 focus reminders while paused; new end 21:53:14 | Pass | `c2`, `c3_world_*`, reminders log |
| M3-P08 | Positive | Background accuracy | App backgrounded 60 s | Remaining time follows the wall clock | 11:50 at 21:41:22 for a 21:53:14 end (≈ screenshot latency) | Pass | `c4_world_focus_after_background_60s` |
| M3-P09 | Positive | Survives app restart | Kill and reinstall the app mid-session | Same session restored with correct remaining time; Campus shows a Focus card | 13:18 left at 21:39:00 for a 21:52:18 end | Pass | `c1_world_focus_after_restart_home`; unit test |
| M3-P10 | Positive | Completion + history | Let the session finish (app backgrounded, reopened after the due time) | Completion state with the exact focused time; history entry; today's total | "Session complete · 15 min 0 s of 15 min"; history "15 of 15 min · completed"; Today 1 · 15 min | Pass | `d0_world_focus_session_complete`, unit tests |
| M3-P10b | Positive | Completion notification | Same session; notification permission granted | A local notification within Android's inexact window | **Not observed.** Android gave the alarm a +5 min 38 s window. Reopening the app inside that window completed the session in-app and cancelled the alarm, so no notification was posted | **Not verified** | `dumpsys alarm` window; reminder scheduling verified (M3-P06/07) |
| M3-P11 | Positive | Back to academic screens | Back to campus → Timetable tab | Existing screens still work | As expected | Pass | widget test |
| M3-N01 | Negative | Moving desks during a session | Tap another desk while focusing | Refused with an explanation; other desks shown locked | As expected | Pass | widget test; `c0` (dimmed desks) |
| M3-N02 | Negative | Second concurrent session | `startFocus` while one is active | StateError, nothing saved | As expected | Pass | `focus_test.dart` |
| M3-N03 | Negative | Invalid duration | 4 or 181 minutes | Rejected (5–180) | As expected | Pass | `focus_test.dart` |
| M3-N04 | Negative | Corrupt stored session | Garbage in storage | Discarded, no crash | As expected | Pass | `focus_test.dart` |
| M3-N05 | Negative | Session finished while the app was closed | Reopen 60 min after a 15-min start | Completed at its exact due time (not "still running", not extended) | As expected | Pass | `focus_test.dart` |
| M3-N06 | Negative | Non-classroom spaces | Tap Library / facilities on a floor plan | Library opens the study-space entry; other facilities show "not used for scheduled classes", never "free" | As expected | Pass | `b7_world_library_entry_sheet` |

### Defects found while exercising the prototype (fixed)
1. Reminder times dropped seconds, so a focus-completion notification could fire up to 59 s early. The completion time now includes seconds (device check: 21:52:**18**).
2. Signpost labels and the "Today on campus" header could overflow with longer labels or large text. They now ellipsize, and the signposts are wider.
3. A free-period label in the timetable could overflow at narrow widths or large text. It now wraps.
4. The seated character was drawn on top of the desk. It's now drawn behind it.
5. The campus character's home spot sat under the Notices signpost. It moved to the open path.
6. The Campus Focus card didn't count down. It now ticks every second (`c7_world_focus_card_ticking`: 7:28 → 7:21).
7. After completion, re-entering the library showed the character at the entrance. The seat is now restored for the just-finished session too.

---
## Milestone 4: release APK and submission readiness (2026-10-20, ~22:40)

**Build command** (from `<repo>\app`): `flutter build apk --release`
**Output:** `app\build\app\outputs\flutter-apk\app-release.apk`, 67,528,177 bytes (64.4 MB), package `com.campussync.campussync`, versionName 1.0.0, versionCode 1, minSdk 24, targetSdk 36, label "CampusSync". Signed with the debug key (installable for demonstration; not a Play Store release). No Firebase config bundled, so it starts in labelled demo mode. No secrets in the repository or APK inputs (checked for private keys and API keys).

**Automated:** `flutter analyze` no issues · `flutter test` **84/84** (run after the last code change).

### Release-build checks (Pixel_9 emulator, clean install)
| ID | Type | Check | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|---|
| M4-P01 | Positive | Clean install + cold start of the release APK | Welcome screen, no errors | `am start` status ok, TotalTime 2573 ms, 0 Flutter errors | Pass (after fix 1) | `e0_release_apk_first_launch` |
| M4-P02 | Positive | Demo profile → Campus | Greeting, Div B data, "Demo data" badge | As expected | Pass | `e1_release_campus` |
| M4-P03 | Positive | Timetable / Rooms / Exams tabs | Render with correct data | As expected; exams OR 17 Nov … IVP 27 Nov | Pass | `e2`–`e4_release_*` |
| M4-P04 | Positive | Library → desk → 25-min focus | Character seated; countdown | 24:57 shown | Pass | `e5_release_library_focus` |
| M4-P05 | Positive | Permission request from Settings | "Allow notifications" → Android prompt → Allow → reminders scheduled | Settings shows 6 scheduled; `dumpsys alarm` lists focus end 22:59:13 + 5 exam reminders | Pass (after fix 2) | `e6`–`e8_release_*` |
| M4-N01 | Negative | Notifications blocked on a fresh install | Honest notice, nothing claimed | "Notifications are turned off … reminders will not appear" | Pass | `e6_release_allow_notifications` |

### Defects found in the release build (fixed)
1. **Release-only startup failure (critical).** R8 code shrinking renamed classes that the `shared_preferences` plugin's Dart JNI bridge looks up by name: first `SharedPreferencesApiRegistrar.getAll`'s signature, then `kotlin.coroutines` types, then `kotlin.Result`. The app stayed on the splash screen. Debug builds don't shrink, so earlier testing couldn't show it. Fix: R8 shrinking disabled for release (`isMinifyEnabled = false`, `isShrinkResources = false` in `android/app/build.gradle.kts`). The partial keep rules are kept and documented in `android/app/proguard-rules.pro` for re-enabling later. Cost: the APK grew from 57.9 MB to 64.4 MB.
2. **Notification permission never requested by default.** Exam and deadline reminders are on by default, but a fresh install only asked for permission when a switch was toggled. Settings now shows an "Allow notifications" action whenever Android blocks notifications.
3. **Focus-completion notification cancelled by the app itself (found by observation).** Release APK, app left in the background (process alive, frozen), never opened: the alarm fired at 23:03:12, and Android logged `Cannot find enqueued record for key 0|com.campussync.campussync|838821820` (the focus reminder ID), and no notification remained. Cause: on wake-up, the Campus focus card's 1-second timer settled the due session, which rescheduled reminders; `NotificationService.replaceAll()` began with `cancelAll()`, which also removes already-delivered notifications. Fix: `replaceAll()` now uses `cancelAllPendingNotifications()` (pending alarms only). M3-P10b was a real defect, not only an unobserved case.
   **Re-test after the fix: inconclusive.** A 15-minute session was started on the fixed release APK at 23:14:38 (alarm scheduled for 23:29:37). Before it was due, the system ran low on memory and the Android emulator was stopped by the development tool, so delivery could not be observed. Status stays **not verified**: run `docs/PHYSICAL_DEVICE_CHECKLIST.md` §5 on a phone (or repeat on the emulator).

---
## Security hardening H1–H4 (2026-10-21; local emulators only, nothing deployed)

**Automated:** `flutter analyze` no issues · `flutter test` **89/89** · `npm run test:rules` **33/33** · `npm run test:seed` **9/9** · `node e2e/run_all.mjs` **74/74 checks, 4/4 suites**. All against the Local Emulator Suite or demo data; no production project was contacted.

| ID | Type | Check | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|---|
| H1-P01 | Positive | Verified user registers profile + SAP claim in one transaction | Allowed | Allowed | Pass | rules test |
| H1-N01 | Negative | Unverified account claims a SAP ID / registers | Denied | Denied | Pass | rules test; RG-02 |
| H1-N02 | Negative | Claim without a profile; two claims in one registration; second claim by an account with a profile | Denied | Denied | Pass | rules tests |
| H1-N03 | Negative | Claim on behalf of another uid; transfer of an existing claim (even by admin) | Denied | Denied | Pass | rules tests |
| H1-N04 | Negative | Second account submits an already-claimed SAP ID (Chrome) | Clear message, nothing written | "This SAP ID is already registered…", no profile | Pass | RG-06/07, `f0_registration_duplicate_sap` |
| H1-P02 | Positive | Admin "Release SAP ID": claimant suspended, claim deleted, audited; rightful student then registers | Works | Works | Pass | rules test; RG-09–RG-11 |
| H1-N05 | Negative | Release while holder active; release by content manager/student; re-activating a released account | Denied | Denied | Pass | rules tests; logic_test |
| H2-P01 | Positive | Profile stores the verified sign-in email; prefilled after verification (Chrome) | Email = Auth email | Equal | Pass | RG-05/05b |
| H2-N01 | Negative | Spoofed email, extra field (`role`), foreign uid, missing field | Denied | Denied | Pass | rules tests |
| H2-N02 | Negative | 11 malformed values (name, roll, group, batch, avatar, client `createdAt`) + non-numeric SAP | Denied | Denied | Pass | rules test |
| H2-N03 | Negative | Self-edit with 5000-char name, non-string batch, or email change | Denied | Denied | Pass | rules test |
| H2-P02 | Positive | Approval card labels verified email vs self-declared identifiers | Labels shown | Shown | Pass | RG-08, `f1_admin_identity_labels` |
| H3-P01 | Positive | All 27 seeded calendar events and 124 exams have an explicit valid status | Yes | Yes | Pass | logic_test; seed test |
| H3-N01 | Negative | Missing/invalid status in the app model | Treated as draft | Draft | Pass | logic_test |
| H3-N02 | Negative | Event without status in Firestore; staff write with missing/invalid status | Hidden / denied | Hidden / denied | Pass | rules tests |
| H3-P02 | Positive | Demo mode shows students exactly the events the Firestore status query returns | Same set (27) | Same | Pass | logic_test |
| H4-P01 | Positive | Seed re-run keeps an admin's room edit and archived exam; creates 0 | Kept | Kept | Pass | seed test (emulator) |
| H4-N01 | Negative | Seed writes announcements/importJobs/admins | Never | 0 documents | Pass | seed test |
| H4-N02 | Negative | Live write without `--confirm-live`; `--admin`; `--emulator-test-users` on live; remote emulator host | Refused before connecting | Refused | Pass | seed tests (fictitious project id) |
| H4-P02 | Positive | `bootstrap_admin.mjs` with verified account | Admin created with Auth email + audit | Created | Pass | seed test |
| H4-N03 | Negative | Bootstrap for unverified/unknown account, or when an admin exists | Refused | Refused | Pass | seed test |

**Defect found and fixed during this work:** on web, a refused registration showed the raw Firestore error (`[cloud_firestore/permission-denied] evaluation error at L136…`) because transaction errors arrive wrapped, not as `FirebaseException`. `FirestoreRepository.registerProfile` now maps them to the friendly message (RG-06).

**Not verified:** anything against the live project (rules not deployed); Android emulator-mode run after adding `google-services.json`.

---
## Post-audit fixes F1–F4 (2026-10-21; local only, nothing deployed)

**Automated (current code):** `flutter analyze` no issues · `flutter test` **93/93** · rules tests **40/40** (throwaway Firestore emulator on ports 8181/9199; the shared emulator on 8080/9099 was not stopped, reset or written) · seed safety **7/7** unit + **9/9** with emulator integration (same throwaway emulator).
**Chrome E2E:** not re-run (F5). `run_all.mjs` deletes all data in the shared local emulator, and the scripts, web builds (fixed ports 8080/9099) and seed host check can't point at an isolated emulator without tooling changes. The last result (74/74) predates F1/F2 and is **pending re-verification**.

| ID | Type | Check | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|---|
| F1-N01 | Negative | **Regression (audit probe B):** a stale squatter card releases the claim of the suspended rightful owner | Denied | Denied | Pass | rules test "REGRESSION (audit probe B)…" |
| F1-N02 | Negative | Stale card with the squatter marked or unmarked; owner suspended, pending or active | Denied | Denied | Pass | rules test |
| F1-N03 | Negative | Mark student A released while deleting the claim of student B (B active, then suspended) | Denied | Denied | Pass | rules test |
| F1-N04 | Negative | Release or mark when the claim is missing | Denied | Denied | Pass | rules test |
| F1-N05 | Negative | Repeated release of an already-released student | Denied (rules); reported "already released" (app) | As expected, no extra audit record | Pass | rules test; logic_test; admin_students_test |
| F1-N06 | Negative | Marker set without deleting the claim, with the student left active, by the student, or at registration | Denied | Denied | Pass | rules test |
| F1-P01 | Positive | Valid release via the repository's read-then-write transaction | Suspended + `sapReleased` + claim deleted + audit | As expected | Pass | rules test |
| F1-P02 | Positive | Demo mode mirrors Firestore (stale card → "already released", owner's claim intact; unknown card → refused, nothing changed) | Consistent | Consistent | Pass | logic_test (2) |
| F2-P01 | Positive | Release and Approve hidden for released accounts; "SAP ID released" label shown | As described | As described | Pass | admin_students_test |
| F2-N01 | Negative | Release from a stale card after another admin already released | Confirmation shown, then "already released … Nothing changed.", no "Failed", no audit duplicate | As expected | Pass | admin_students_test |

**Defect found while testing F2 (fixed):** `_AsyncListState._reload` in `admin_people.dart` passed an arrow closure returning a Future to `setState`, so every list reload after Approve, Suspend or Release asserted in debug builds. It now uses a block body.

---
## M1 Android startup fix and isolated Chrome E2E (2026-10-21; nothing deployed, production not contacted)

**Automated:** `flutter analyze` no issues · `flutter test` **93/93** · rules **40/40** and seed safety **9/9** (throwaway emulators on 8181/9199) · seed unit **7/7** · Chrome E2E `node run_isolated.mjs` **78/78 checks, 4/4 suites** against a dedicated emulator (127.0.0.1:8180/9180, `demo-campussync-e2e`). The shared emulator (8080/9099) kept the same processes and identical document counts before and after (students 5, rooms 131, auditLogs 2, announcements 0).

| ID | Type | Check | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|---|
| M1-N01 | Negative | **Before fix:** emulator-mode debug APK on Pixel_9 | — | `FirebaseInitProvider: FirebaseApp initialization successful`, then `Unhandled Exception: [core/duplicate-app]`; stuck on splash | Defect confirmed | `g0_android_emulator_mode_duplicate_app_before_fix` |
| M1-P01 | Positive | After removing `FirebaseInitProvider`: emulator mode starts | Welcome screen, no duplicate-app | As expected; provider absent from merged manifest | Pass | `g1_android_emulator_mode_after_fix` |
| M1-P02 | Positive | Demo mode starts without Firebase | No Firebase initialisation | 0 Firebase log lines; demo welcome | Pass | logcat |
| M1-P03 | Positive | Live mode starts (AVD in airplane mode, no network) | Sign-in screen, no duplicate-app | As expected; build replaced before the network was restored | Pass | logcat |
| M1-P04 | Positive | Emulator mode on Android signs in against a dedicated emulator via `10.0.2.2:8180/9180` | Home shows the TEST Div B student | As expected; dedicated Auth emulator recorded the login (02:41:13), the shared one didn't | Pass | `g2_android_emulator_mode_signed_in_dedicated_emulator` |
| E2E-N01 | Negative | E2E scripts with no endpoints, shared ports, a remote host, or a non-demo project | Refused before any request | All four refused | Pass | `env.mjs` |
| E2E-N02 | Negative | Network interlock with a stale student build compiled for 8080 | Request aborted in the browser | `127.0.0.1:8080/…Firestore/Listen` blocked; shared auditLogs unchanged (2) | Pass | interlock run |

---
## Re-verification before final rubric review (2026-10-21; no code changes)

All suites were re-run on the unchanged final code. Nothing was deployed and production wasn't contacted. The shared emulator (8080/9099) kept the same processes and identical document counts (students 5, rooms 131, auditLogs 2).

| Suite | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | 93/93 |
| Rules (throwaway emulator) | 40/40 |
| Seed safety, unit | 7/7 |
| Seed safety, with emulator | 9/9 |
| Chrome E2E (`node run_isolated.mjs`, dedicated emulator) | 78/78, 4/4 suites. Log: `docs/evidence/e2e_chrome_isolated_run_2026-10-21.txt` |

**Finding (not a test failure):** the Chrome run logged 29 uncaught page errors on the admin dashboard (17 in the rooms & announcements suite, 12 in the exams & access suite): `Cannot read properties of null (reading 'toString')` in Flutter's web keyboard converter (`_handleEvent`). Bisection with synthetic puppeteer keystrokes shows they occur only for `/`, `-`, `*` and `+`, the keys that also exist on the numeric keypad. Letters, digits, `@`, `.`, `:`, uppercase, Ctrl+A and Backspace cause none. The character is still entered (AN-04 saved the URL exactly). This is engine code, not CampusSync code. **Not verified:** whether a real hardware keyboard triggers it (manual check: type a URL into an admin text field in Chrome with DevTools open).

---
## Registration errors and security findings M2, M3, M4, L1, L2, L3 (2026-10-21; local only, nothing deployed)

**Automated (final code):** `flutter analyze` no issues · `flutter test` **107/107** · rules **61/61** (throwaway emulator, ports 8181/9199) · seed safety **7/7** unit and **9/9** with emulator · Chrome E2E `node run_isolated.mjs` **81/81 checks, 4/4 suites** (dedicated emulator 8180/9180). Log: `docs/evidence/e2e_chrome_isolated_run_2026-10-21_m2-m4.txt`. The shared emulator (8080/9099) kept the same processes and document counts (students 5, rooms 131, auditLogs 2).

| ID | Type | Check | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|---|
| RE-P01 | Positive | Error codes read from `FirebaseException` and from the web-wrapped text seen in the earlier E2E run | Code extracted | As expected | Pass | `registration_errors_test.dart` |
| RE-N01 | Negative | Denied claim check vs denied write vs offline vs other errors | duplicate / rejected details / network / unexpected (code only) | As expected; no raw rule text in any message | Pass | `registration_errors_test.dart` (7 tests) |
| RE-N02 | Negative | Restored but unverified session submits a profile | Refused before any lookup; nothing claimed | As expected | Pass | `registration_form_test.dart` |
| RE-N03 | Negative | Duplicate SAP ID in Chrome | "This SAP ID is already registered…" | As expected | Pass | E2E RG-06 |
| RE-N04 | Negative | Submit while the browser is offline | Network message, nothing saved, retry works | "No internet connection…" (from the sign-in token refresh), no profile or claim, retry succeeded | Pass | E2E RG-12–RG-14 |
| M2-P01 | Positive | Div B student queries announcements and exams as the app does | All + Div B + department announcements; own-group and chosen-elective exams | As expected (E2E: 5 exams visible, 119 hidden) | Pass | rules "Audience enforcement (M2)"; E2E EX-12 |
| M2-N01 | Negative | Read another group's announcement or exam by id, by asking for its key, or with no audience filter | Denied | Denied | Pass | rules tests |
| M2-N02 | Negative | `audienceKeys` inconsistent with the audience (wrong scope, empty, `all` on an exam) | Denied | Denied | Pass | rules tests |
| M2-P02 | Positive | Server filter equals the app filter (`Exam.appliesTo`) for all 124 seeded exams | Equal | Equal | Pass | `audience_test.dart` |
| M3-N01 | Negative | 14 invalid announcements (`javascript:`/`ftp:` URL, URL with a space or over 2048 characters, oversized description/summary/source, bad category/date/title, extra field, bad audience, `reviewFlags` not a list) and an id mismatch | Denied | Denied | Pass | rules "Announcement validation (M3)" |
| M4-N01 | Negative | Content write without an audit record, with a non-existent or reused audit id, or with an audit naming another uid or email | Denied | Denied | Pass | rules "Audit enforcement (M4)" |
| M4-P01 | Positive | All admin workflows through the UI with the audit requirement in force | Pass | 81/81 E2E | Pass | E2E log |
| L1-N01 | Negative | Change entries or dates of a published or archived version; published → draft | Denied | Denied | Pass | rules "Timetable version immutability (L1)" |
| L1-P01 | Positive | Archive, roll back (archived → published), edit and publish a draft | Allowed | Allowed; E2E publish and rollback pass | Pass | rules tests; E2E timetable 17/17 |
| L2-N01 | Negative | Admin removes or demotes self; removed or demoted admin acts against the remover | Denied | Denied | Pass | rules "Administrator removal (L2)" |
| L3-N01 | Negative | `admins` doc with role `Admin` (typo) or no role: read staff data or write | Denied | Denied | Pass | rules "Admin role values (L3)" |

**Test updated (not weakened):** E2E EX-12 previously asserted that a student could read all 124 published exams ("other streams readable but unlinked"). That was the M2 gap itself. It now asserts that the student sees exactly the exams for their audience.

**Not covered:**
- concurrent mutual admin removal (L2);
- deletes binding an audit record (M4, documented);
- the Firestore-level offline message in a real browser: there the token refresh fails first, so it's unit-tested only;
- the 29 known Flutter keyboard page errors in the admin E2E (unchanged).
