import 'dart:convert';
import 'dart:io';

import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/repository.dart';
import 'package:campussync/domain/availability.dart';
import 'package:campussync/domain/models.dart';
import 'package:campussync/domain/reminders.dart';
import 'package:campussync/domain/schedule.dart';
import 'package:campussync/domain/validators.dart';
import 'package:flutter_test/flutter_test.dart';

const divB = 'btech-computer-2026-27-sem5-div-b';
const actor = Actor('admin-1', 'admin@example.com');

Map<String, dynamic> seed() => {
  for (final f in Directory('assets/seed').listSync().whereType<File>())
    f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
};

void main() {
  group('Input validation (positive)', () {
    test('valid email, password, SAP ID, roll number and name are accepted', () {
      expect(Validators.email('student@example.edu'), isNull);
      expect(Validators.password('campus2026'), isNull);
      expect(Validators.confirmPassword('campus2026', 'campus2026'), isNull);
      expect(Validators.sapId('99999300123'), isNull);
      expect(Validators.rollNumber('b001', division: 'B'), isNull);
      expect(Validators.displayName("Test D'Souza"), isNull);
      expect(Validators.optionalUrl('https://example.org/register'), isNull);
      expect(Validators.optionalUrl(''), isNull);
    });
  });

  group('Input validation (negative)', () {
    test('empty and malformed email', () {
      expect(Validators.email(''), 'Email is required.');
      expect(Validators.email('student@'), contains('valid email'));
      expect(Validators.email('student.nmims.edu'), contains('valid email'));
    });
    test('weak or mismatched password', () {
      expect(Validators.password('short1'), contains('at least 8'));
      expect(Validators.password('onlyletters'), contains('letter and one number'));
      expect(Validators.confirmPassword('abc12345', 'abc12346'), 'Passwords do not match.');
    });
    test('SAP ID boundaries', () {
      expect(Validators.sapId('1234567'), contains('8 to 12'));
      expect(Validators.sapId('1234567890123'), contains('8 to 12'));
      expect(Validators.sapId('12345678'), isNull);
      expect(Validators.sapId('123456789012'), isNull);
      expect(Validators.sapId('7002A300123'), contains('digits only'));
    });
    test('roll number format and division mismatch', () {
      expect(Validators.rollNumber('B01'), contains('3 digits'));
      expect(Validators.rollNumber('C001', division: 'B'), contains('start with B'));
    });
    test('unsafe links and reversed dates are rejected', () {
      expect(Validators.optionalUrl('javascript:alert(1)'), isNotNull);
      expect(Validators.optionalUrl('ftp://files.example.org'), isNotNull);
      expect(Validators.dateRange(DateTime(2026, 10, 2), DateTime(2026, 10, 1)), isNotNull);
      expect(Validators.title('x' * 141), contains('140'));
    });
  });

  group('Timetable versioning', () {
    TimetableVersion v(int n, VersionStatus st, {DateTime? from, DateTime? to}) => TimetableVersion(
      id: 'g-v$n',
      groupId: 'g',
      version: n,
      status: st,
      effectiveFrom: from ?? DateTime(2026, 7, 13),
      effectiveTo: to ?? DateTime(2026, 11, 5),
    );

    test('publishing archives the overlapping published version and stamps the publisher', () {
      final writes = planPublish(
        v(2, VersionStatus.draft),
        [v(1, VersionStatus.published), v(2, VersionStatus.draft)],
        actor,
        DateTime(2026, 8, 1),
      );
      expect(writes.map((w) => '${w.id}:${w.status.name}'), ['g-v1:archived', 'g-v2:published']);
      expect(writes.last.publishedBy, actor.email);
    });

    test('non-overlapping published versions (next term) are kept', () {
      final next = v(2, VersionStatus.draft, from: DateTime(2027, 1, 2), to: DateTime(2027, 4, 23));
      final writes = planPublish(next, [v(1, VersionStatus.published)], actor, DateTime.now());
      expect(writes.single.id, 'g-v2');
    });

    test('version numbers increase per group', () {
      expect(nextVersionNumber('g', [v(1, VersionStatus.archived), v(3, VersionStatus.published)]), 4);
      expect(nextVersionNumber('new', [v(1, VersionStatus.published)]), 1);
    });
  });

  group('Demo repository admin workflow', () {
    test('draft is hidden from students until published; rollback restores previous version', () async {
      final repo = DemoRepository(seed());
      final base = (await repo.fetch(asAdmin: true)).versions.firstWhere((x) => x.groupId == divB);
      final revised = base.copyWith(
        id: '$divB-v2',
        version: 2,
        status: VersionStatus.draft,
        entries: base.entries.where((e) => e.subjectCode != 'OR').toList(),
      );
      await repo.saveDraftVersion(revised, actor);

      var student = await repo.fetch(asAdmin: false);
      expect(student.versions.where((x) => x.groupId == divB).single.version, 1, reason: 'draft must stay invisible');

      await repo.publishVersion(revised, (await repo.fetch(asAdmin: true)).versions, actor);
      student = await repo.fetch(asAdmin: false);
      expect(student.versions.where((x) => x.groupId == divB).single.version, 2);
      final orCount = student.availability.usesOn(DateTime(2026, 7, 20)).where((u) => u.group.id == divB && u.entry.subjectCode == 'OR');
      expect(orCount, isEmpty);

      final archivedV1 = (await repo.fetch(asAdmin: true)).versions.firstWhere((x) => x.id == base.id);
      expect(archivedV1.status, VersionStatus.archived);
      await repo.publishVersion(archivedV1, (await repo.fetch(asAdmin: true)).versions, actor);
      student = await repo.fetch(asAdmin: false);
      expect(student.versions.where((x) => x.groupId == divB).single.version, 1);
      expect((await repo.listAudit()).map((a) => a.action), containsAll(['timetable.saveDraft', 'timetable.publish']));
    });

    test('published versions cannot be edited in place', () async {
      final repo = DemoRepository(seed());
      final published = (await repo.fetch(asAdmin: true)).versions.first;
      expect(() => repo.saveDraftVersion(published, actor), throwsA(isA<RepositoryException>()));
    });

    test('a newly added group with a published timetable affects room availability', () async {
      final repo = DemoRepository(seed());
      const g = AcademicGroup(id: 'it-sem5-a', type: 'division', academicYearId: 'ay-2026-27', semester: 5, label: 'IT Sem V Div A');
      await repo.saveGroup(g, actor);
      final monday = DateTime(2026, 7, 20);
      expect((await repo.fetch(asAdmin: false)).availability.check('CR-301', monday, 600, 660).status, RoomStatus.noKnownClass);
      final v = TimetableVersion(
        id: 'it-v1',
        groupId: g.id,
        version: 1,
        status: VersionStatus.draft,
        effectiveFrom: DateTime(2026, 7, 13),
        entries: const [
          TimetableEntry(id: 'x', weekday: 1, startMin: 600, endMin: 660, kind: EntryKind.lecture, subjectCode: 'SE', roomId: 'CR-301'),
        ],
      );
      await repo.publishVersion(v, const [], actor);
      expect((await repo.fetch(asAdmin: false)).availability.check('CR-301', monday, 600, 660).status, RoomStatus.occupied);
    });

    test('admins cannot change their own role; duplicate SAP IDs are rejected', () async {
      final repo = DemoRepository(seed());
      expect(() => repo.setAdmin(actor.uid, actor.email, null, actor), throwsA(isA<RepositoryException>()));
      const p = StudentProfile(uid: 'u1', email: 'a@b.co', displayName: 'A', sapId: '99999300123', rollNumber: 'B001');
      await repo.registerProfile(p);
      expect(
        () => repo.registerProfile(
          const StudentProfile(uid: 'u2', email: 'c@d.co', displayName: 'C', sapId: '99999300123', rollNumber: 'B002'),
        ),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('releasing a wrongly claimed SAP ID suspends the claimant and frees the ID for the real student', () async {
      final repo = DemoRepository(seed());
      const squatter = StudentProfile(uid: 'u1', email: 'a@b.co', displayName: 'A', sapId: '99999300123', rollNumber: 'B001');
      await repo.registerProfile(squatter);
      expect(() => repo.registerProfile(squatter), throwsA(isA<RepositoryException>()), reason: 'one profile per account');
      expect(await repo.releaseSapId(squatter, actor), SapRelease.released);
      final released = (await repo.loadProfile('u1'))!;
      expect(released.status, AccountStatus.suspended);
      expect(released.sapReleased, isTrue);
      expect(
        () => repo.setStudentAccount('u1', status: AccountStatus.active, groupId: divB, actor: actor),
        throwsA(isA<RepositoryException>()),
        reason: 'a released account cannot be re-activated',
      );
      await repo.registerProfile(
        const StudentProfile(uid: 'u2', email: 'c@d.co', displayName: 'C', sapId: '99999300123', rollNumber: 'B002'),
      );
      expect((await repo.loadProfile('u2'))!.sapId, '99999300123');
      expect((await repo.listAudit()).first.action, 'student.releaseSapId');
    });

    test('F1: a stale card never releases the claim of another student, even a suspended one', () async {
      final repo = DemoRepository(seed());
      const squatter = StudentProfile(uid: 'u1', email: 'a@b.co', displayName: 'A', sapId: '99999300123', rollNumber: 'B001');
      const owner = StudentProfile(uid: 'u2', email: 'c@d.co', displayName: 'C', sapId: '99999300123', rollNumber: 'B002');
      await repo.registerProfile(squatter);
      await repo.releaseSapId(squatter, actor);
      await repo.registerProfile(owner);
      await repo.setStudentAccount('u2', status: AccountStatus.suspended, actor: actor);
      final audits = (await repo.listAudit()).length;
      // The admin's list still shows the squatter's pre-release card.
      expect(await repo.releaseSapId(squatter, actor), SapRelease.alreadyReleased);
      expect((await repo.loadProfile('u2'))!.sapReleased, isFalse);
      expect(
        () => repo.registerProfile(const StudentProfile(uid: 'u3', email: 'e@f.co', displayName: 'E', sapId: '99999300123', rollNumber: 'B003')),
        throwsA(isA<RepositoryException>()),
        reason: 'the owner still holds the claim',
      );
      expect((await repo.listAudit()).length, audits, reason: 'a no-op release writes no audit record');
    });

    test('F1: a card that does not match a stored claim holder releases nothing', () async {
      final repo = DemoRepository(seed());
      const holder = StudentProfile(uid: 'u1', email: 'a@b.co', displayName: 'A', sapId: '99999300123', rollNumber: 'B001');
      await repo.registerProfile(holder);
      // A card for an account with no stored profile, naming the holder's SAP ID.
      const stranger = StudentProfile(uid: 'nobody', email: 'x@y.z', displayName: 'X', sapId: '99999300123', rollNumber: 'B009');
      await expectLater(repo.releaseSapId(stranger, actor), throwsA(isA<RepositoryException>()));
      final p = (await repo.loadProfile('u1'))!;
      expect([p.status, p.sapReleased], [AccountStatus.pending, false]);
      expect(await repo.releaseSapId(holder, actor), SapRelease.released, reason: 'the claim was left intact');
    });
  });

  group('Publication status (calendar, exams, announcements)', () {
    test('every seeded calendar event and exam has an explicit valid status', () {
      final s = seed();
      final events = (s['calendar']['events'] as List).cast<Map<String, dynamic>>();
      final exams = (s['exams']['exams'] as List).cast<Map<String, dynamic>>();
      final names = PublishStatus.values.map((v) => v.name).toSet();
      expect(events, isNotEmpty);
      for (final e in [...events, ...exams]) {
        expect(names, contains(e['status']), reason: '${e['id']} needs draft/published/archived');
      }
    });

    test('missing or invalid status is treated as draft, never as published', () {
      expect(PublishStatus.parse(null), PublishStatus.draft);
      expect(PublishStatus.parse('live'), PublishStatus.draft);
      expect(PublishStatus.parse(42), PublishStatus.draft);
      expect(PublishStatus.parse('archived'), PublishStatus.archived);
      final event = {...(seed()['calendar']['events'] as List).first as Map<String, dynamic>}..remove('status');
      expect(CalendarEvent.fromJson(event).status, PublishStatus.draft);
      expect(CalendarEvent.fromJson({...event, 'status': 'bogus'}).status, PublishStatus.draft);
      final exam = Exam.fromJson({...(seed()['exams']['exams'] as List).first as Map<String, dynamic>}..remove('status'));
      expect(exam.status, PublishStatus.draft);
    });

    test('students see the same calendar events in demo mode as the Firestore status query returns', () async {
      final s = seed();
      final events = (s['calendar']['events'] as List).cast<Map<String, dynamic>>();
      // Firestore: where('status', isEqualTo: 'published') never matches a missing field.
      final firestoreVisible = events.where((e) => e['status'] == 'published').map((e) => e['id']).toSet();
      final template = Map<String, dynamic>.from(events.first);
      (s['calendar']['events'] as List)
        ..add({...template, 'id': 'no-status'}..remove('status'))
        ..add({...template, 'id': 'draft', 'status': 'draft'})
        ..add({...template, 'id': 'invalid', 'status': 'live'});
      final demoVisible = (await DemoRepository(s).fetch(asAdmin: false)).calendarEvents.map((e) => e.id).toSet();
      expect(demoVisible, firestoreVisible);
      expect(demoVisible.length, 27);
    });
  });

  group('Reminder planning', () {
    test('class reminders honour lead time, skip breaks and past classes, and have stable keys', () async {
      final data = await DemoRepository(seed()).fetch(asAdmin: false);
      final svc = ScheduleService(data.availability, settings: data.settings);
      const profile = ScheduleProfile(groupId: divB, batch: 'B1');
      final now = DateTime(2026, 7, 20, 9, 0); // Monday, during the 08-10 lab
      final r = planReminders(now: now, schedule: svc, profile: profile, classes: true, leadMinutes: 10, days: 1);
      expect(r.first.at, DateTime(2026, 7, 20, 9, 50)); // SE lecture at 10:00
      expect(r.any((x) => x.title.contains('break')), isFalse);
      final again = planReminders(now: now, schedule: svc, profile: profile, classes: true, leadMinutes: 10, days: 1);
      expect(again.map((x) => x.key), r.map((x) => x.key));
    });

    test('disabled reminders and unpublished deadlines produce nothing', () {
      final r = planReminders(
        now: DateTime(2026, 7, 20),
        deadlines: [Announcement(id: 'a', title: 'Draft', endDate: DateTime(2026, 8, 1))],
        deadlineReminders: true,
        exams: [
          Exam(id: 'e', groupIds: const [divB], subjectCode: 'SE', subjectName: 'SE', date: DateTime(2026, 11, 16)),
        ],
        examReminders: false,
      );
      expect(r, isEmpty);
    });

    test('exam reminder fires the evening before', () {
      final r = planReminders(
        now: DateTime(2026, 11, 1),
        exams: [
          Exam(id: 'e', groupIds: const [divB], subjectCode: 'SE', subjectName: 'Software Engineering', date: DateTime(2026, 11, 16)),
        ],
        examReminders: true,
      );
      expect(r.single.at, DateTime(2026, 11, 15, 18));
    });
  });
}
