# CampusSync – Architecture

## Overview
A modular monolith with two Flutter clients over a managed backend:

```
 Student app (Android, Flutter)        Admin dashboard (Flutter Web, lib/main_admin.dart)
        │  shared: domain/ + data/ + ui/theme                │
        └──────────────┬──────────────────────────────────────┘
                       ▼
        CampusRepository (interface, lib/data/repository.dart)
          ├─ FirestoreRepository  → Firebase Auth + Cloud Firestore (rules in firebase/firestore.rules)
          └─ DemoRepository       → bundled seed JSON (used when Firebase is not configured)
        LocalCache (shared_preferences): last-synced snapshot, saved announcements, profile, prefs
        NotificationService (flutter_local_notifications): device-scheduled reminders
```

## Code layout (`app/lib`)
| Folder | Responsibility |
|---|---|
| `domain/` | Pure Dart: models, **AvailabilityEngine**, ScheduleService, TimetableValidator, TimetableImporter (CSV/JSON), reminder planning, validators. No Flutter imports, fully unit-tested. |
| `data/` | CampusData snapshot, repository interface and implementations, AuthService, LocalCache, seed loader. |
| `services/` | Platform services (notifications). |
| `app/` | AppState (ChangeNotifier via `provider`), bootstrap (Firebase or demo). |
| `ui/` | Student screens (onboarding, campus, timetable, rooms, updates, settings), admin screens, theme and shared widgets. |

## Availability engine
For a date and interval, the engine:
1. Takes every **active** academic group.
2. Finds that group's **highest-numbered published version** effective on that date.
3. Collects non-cancelled entries with a room on that weekday. Breaks and library periods are excluded.
4. Marks a room **occupied** if any entry overlaps (`start < end' && start' < end`, so 11:00 boundaries don't clash).
5. Otherwise reports **freeVerified** only if the administrator has declared coverage complete *and* every active group is published. If not, it reports **noKnownClass** with a coverage explanation.
6. Returns the reason, conflicts, next use, free gaps and coverage.

Inactive, non-schedulable and unknown rooms are reported as unavailable or unknown, never as free. New groups and versions take part automatically because nothing is hard-coded to Div B/C.

## Firestore data model
| Collection | Key fields |
|---|---|
| `settings/campus` | timezone, dayStart/dayEnd, coverageDeclaredComplete, coverageNote, institutionName, calendarAudienceLabels |
| `departments`, `programs`, `academicYears` | id, name/label, parent id, active |
| `groups` | type (division/electivePool), programId, departmentId, academicYearId, yearOfStudy, semester, division, batches, active |
| `subjects`, `faculty`, `electives` | code/name; id/name/initials; OE offerings with rooms |
| `rooms` | code, name, type, floorId, capacity, active, bookable, aliases, restrictionNote |
| `floors` | regions (normalised rects) mapped to `roomId` |
| `timetableVersions` | groupId, version, status (draft/published/archived), effectiveFrom/To, source, entries[], createdBy, publishedBy/At |
| `announcements` | status, category, dates, registrationUrl, audience {scope, ids}, source |
| `exams` | groupIds **or** electiveOfferingIds (who sits it), subjectCode, officialCode, stream, date, start/endTime, timeSource (cell/page default), room (null: not in source), **status** (draft/published/archived = withdrawn), source (file + page), reviewFlags |
| `calendarEvents` | title, category, start, end, term, audience, source, **status** |
| `importJobs` | source file, pages, method, counts, errors, warnings, import date (provenance of bulk imports) |
| `students/{uid}` | sapId, rollNumber, requestedGroupId, groupId (admin-set), batch, OE choices, avatar, status |
| `sapIndex/{sapId}` | uid (one account per SAP ID) |
| `admins/{uid}` | role: admin \| contentManager |
| `auditLogs` | actor, action, targetPath, summary, time (append-only) |

All admin writes set `updatedBy`/`updatedAt` and write an audit record in the same batch. Publishing a version is one atomic batch: the new version is marked published and any overlapping published version is archived. Versions are never deleted, so rollback re-publishes an archived version.

## Security model (enforced in `firebase/firestore.rules`)
- Registration has two steps. "Create account" creates only the Firebase Auth account. The profile and SAP ID claim are written after the email is verified, because the rules require `email_verified` in the ID token; the form is prefilled from memory.
- Profiles are created as `pending` with `groupId == null`. They contain only allowlisted fields, each type- and format-checked (name, SAP ID, roll number, division that exists, batch, avatar). `email` must equal the verified sign-in email and `createdAt` must be the server time. Only an admin can set `status`/`groupId`. Students can edit only displayName, avatar, batch and OE choices, with the same validation.
- SAP ID claims (`sapIndex/{sap}`) can only be created in the same write as the claimant's first and only profile. That gives one SAP ID per account and one account per SAP ID; claims can't be transferred. **Recovery:** an admin's "Release SAP ID" re-reads the student and claim in a transaction. If the student still holds their own claim, one audited write marks the profile `sapReleased: true`, suspends it and deletes the claim. The rules delete a claim only when its own holder (the uid stored in the claim, whose profile names that SAP ID) changes from not-released to released and suspended in that same write. A stale card for another student therefore can't delete someone else's claim, even a suspended student's. A repeated release is reported as "already released" without writing. Released accounts can't be re-activated or released again, and the dashboard hides Approve and Release for them.
- **Identity limits:** Firebase Auth proves only control of the sign-in email. Name, SAP ID, roll number and division are self-declared; there is no university roster or SSO to check them against. A person with a verified email can still claim someone else's SAP ID, limited to one per verified account, until an admin checks and releases it. Admins verify identifiers against college records before approving, and the approval screen labels them "Self-declared, unverified". Closing this gap needs an authoritative roster (e.g. an admin-imported SAP ID → college email list) or institutional SSO.
- SAP ID and roll number are identifiers, not credentials.
- Student profiles are readable only by the owner and admins. The SAP index can't be listed.
- Students read only `published` timetable versions, announcements, exams and calendar events, and only once approved. Every record carries an explicit `status`; writes with a missing or unknown status are rejected. The app treats a missing or unknown status as `draft` (`PublishStatus.parse`), so demo, emulator and live modes show students the same records.
- Announcements and exams are readable by a student only if their `audienceKeys` (`all`, `group:<id>`, `dept:<id>`, `oe:<id>`) match the student's group, department or chosen electives. The student app's queries ask for exactly those keys (`studentAudienceKeys`). Staff read everything.
- Announcements are validated field by field: an allowlist, length limits, http(s)-only links, ISO dates, `id` equal to the document id, and an audience consistent with `audienceKeys`.
- Every staff write from the app names, in `auditId`, a new audit record created in the same commit by the same user, and audit records must carry the signed-in user's uid and email. Deletes can't be bound this way (see `docs/SECURITY_AUDIT.md` M4).
- Published and archived timetable versions are frozen: only their status moves (publish, archive, roll back), never back to draft.
- Staff access requires an `admins` document whose `role` is exactly `admin` or `contentManager`.
- Only `admin` can change timetables, rooms, groups, settings and roles. Admins can't change their own role. `contentManager` is limited to announcements, exams and calendar.
- No privileged credentials ship in the client. The live Firebase options (`lib/firebase_options_live.dart`, generated by `flutterfire configure`) are public client identifiers, not secrets; access is enforced by the rules. Service-account keys stay outside the repo.

## Environments
| Mode | How | Backend | Labelled in UI |
|---|---|---|---|
| Demo (default) | no dart-define, or `--dart-define=CAMPUSSYNC_BACKEND=demo` | bundled seed in memory (`DemoRepository`) | "Demo data" / demo banner |
| Local emulator | `--dart-define=CAMPUSSYNC_BACKEND=emulator` (legacy `USE_FIREBASE_EMULATOR=true` still accepted) | Firebase Local Emulator Suite, project `demo-campussync` | "Test env" / test-environment banner |
| Live | `--dart-define=CAMPUSSYNC_BACKEND=live` | real (live) Firebase project (options from `lib/firebase_options_live.dart`) | none (live is never the default) |

## Offline behaviour
After each successful sync the snapshot is cached. If Firestore answers a fetch from its own device cache (`metadata.isFromCache`), the snapshot is labelled *offline copy*, the banner says so, and it is not written over the last good server snapshot. When a fetch fails, the cached snapshot is shown with an "Offline – showing data last synced …" banner. Saved announcements keep a full copy. Firestore's own offline cache also applies on Android. No offline writes are presented as synced.

## Notifications
Reminders are planned in pure Dart (`domain/reminders.dart`) and replace all pending notifications each time, so timetable edits and cancellations never leave stale or duplicate reminders. Android inexact alarms are used, and the UI says delivery may be delayed. Push notifications for server-published updates would need FCM plus a Cloud Function (Blaze plan); `firebase_messaging` is included but not wired, so it isn't claimed as working.

## Input validation and error handling
| Layer | What is validated | Where |
|---|---|---|
| Forms (student + admin) | Required fields (marked `*`), email, password strength, SAP ID (8–12 digits), roll number (division letter + 3 digits), name, https URLs, date ranges, HH:MM times, capacity 1–1000, room code format. Errors appear per field after that field is edited, and all at once on submit | `domain/validators.dart`, field-level `autovalidateMode` |
| Imports | File type (.csv/.json only), empty files, required CSV columns, weekday/time/kind parsing, unknown rooms/faculty → line-level errors; nothing applied until the preview is error-free | `domain/timetable_import.dart` |
| Business rules | Timetables: double-booked rooms, same-batch overlaps, unknown references, empty versions, reversed dates (errors block publish; warnings shown). Exams: duplicates, clashes for shared groups/electives, bad times, unknown links, out-of-window dates, review flags | `domain/timetable_validator.dart`, `domain/exam_validator.dart` |
| Backend | Role, ownership, status values, actor stamping, allowed fields, SAP-ID uniqueness, append-only audit | `firebase/firestore.rules` (18 tests) |
| Runtime errors | Auth errors mapped to plain messages; network failure → cached data with offline banner; Firestore cache-served reads labelled offline; notification permission denial and blocked notifications reported in Settings; dialog errors shown inline | `data/auth_service.dart`, `app/app_state.dart`, `ui/settings` |

## Virtual campus and focus sessions (prototype)
**Rendering approach:** 2.5D in plain Flutter. The isometric campus is drawn with CustomPainter, and interiors and characters are widgets with implicit animations. No game engine, so there are no extra dependencies, the APK stays small, it runs smoothly on the emulator, and every interaction can be widget-tested. A 3D engine (Flame/Unity embedding) was rejected for this stage because of build complexity, APK size, asset needs and weaker testability.

| Piece | File | Notes |
|---|---|---|
| Campus world | `ui/home/campus_world.dart` | Buildings, signposts, ambient animation; the character walks to a building before entering. The "Library · 7F" signpost sits on the Academic Block because the Library is a room on its 7th floor (supplied plan) |
| Character | `ui/world/character.dart` | Drawn body + avatar head; idle/walking/sitting poses; reduce-motion aware. Avatar is stored with the profile; outfit colour is a device-local cosmetic preference |
| Academic Block interior | `ui/world/building_interior.dart` | Lift panel (LG–8), real floor plans and room statuses via the shared `ui/rooms/floor_plan.dart` (same code as the Rooms tab) |
| Library study hall | `ui/world/library_study.dart` | **Conceptual** desk layout (labelled as such); desk selection, seating, focus panel, history |
| Focus logic | `domain/focus.dart` | Pure Dart. Remaining time is derived from `startedAt`, `pausedTotal` and `pausedAt` against the wall clock, so it stays correct across backgrounding and restarts. `settle()` completes a session at its exact due time |
| Focus storage | `data/focus_repository.dart` | `FocusRepository` boundary; `LocalFocusRepository` (SharedPreferences) is the only implementation, labelled "Saved on this device only". A Firestore implementation (`students/{uid}/focusSessions`) can be added without changing callers |
| Reminders | `app/app_state.dart` | A running session adds a completion reminder to the normal reminder plan; pausing removes it, resuming reschedules it |

Not built (by design, for later): multiplayer presence, shared rooms, leaderboards, server-synced sessions. The repository boundary and per-space/per-spot IDs are in place for these.
