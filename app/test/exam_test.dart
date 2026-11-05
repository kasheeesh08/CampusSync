import 'dart:convert';
import 'dart:io';

import 'package:campussync/app/app_state.dart';
import 'package:campussync/data/campus_data.dart';
import 'package:campussync/data/demo_repository.dart';
import 'package:campussync/data/local_cache.dart';
import 'package:campussync/data/repository.dart';
import 'package:campussync/domain/exam_validator.dart';
import 'package:campussync/domain/models.dart';
import 'package:campussync/domain/reminders.dart';
import 'package:campussync/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const divB = 'btech-computer-2026-27-sem5-div-b';
const divC = 'btech-computer-2026-27-sem5-div-c';
const actor = Actor('admin-1', 'admin@example.com');

Map<String, dynamic> seed() => {
  for (final f in Directory('assets/seed').listSync().whereType<File>())
    f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(f.readAsStringSync()),
};

ValidationCheck check(CampusData d, List<Exam> exams) {
  final w = d.termEndExamWindow!;
  final r = validateExams(
    exams,
    groupIds: d.groups.map((g) => g.id).toSet(),
    electiveIds: d.electives.map((e) => e.id).toSet(),
    windowStart: w.start,
    windowEnd: w.end,
  );
  return ValidationCheck(r.errors.map((e) => e.message).toList(), r.warnings.map((e) => e.message).toList());
}

class ValidationCheck {
  final List<String> errors, warnings;
  ValidationCheck(this.errors, this.warnings);
}

Exam exam(String id, String code, DateTime date, {List<String> groups = const [divB], String start = '10:00', String end = '13:00'}) =>
    Exam(id: id, groupIds: groups, subjectCode: code, subjectName: code, date: date, startTime: start, endTime: end);

void main() {
  final data = CampusData.fromSeed(seed());

  group('Exam import (source: final exam timetable PDF, pages 19-24)', () {
    test('Counts match the transcription and every record has provenance', () {
      expect(data.exams, hasLength(124));
      expect(data.exams.where((e) => e.electiveOfferingIds.isNotEmpty), hasLength(36));
      expect(data.exams.every((e) => e.source != null && e.source!.contains('page')), isTrue);
      expect(data.importJobs.single['counts']['records'], 124);
    });

    test('Computer Engineering exams map to both Div B and Div C with official codes and times', () {
      final ce = data.exams.where((e) => e.groupIds.contains(divB)).toList()..sort((a, b) => a.date.compareTo(b.date));
      expect(ce.map((e) => '${e.subjectCode}@${formatDate(e.date)}'), [
        'OR@2026-11-17',
        'AI@2026-11-19',
        'SE@2026-11-23',
        'OS@2026-11-25',
        'IVP@2026-11-27',
      ]);
      expect(ce.every((e) => e.groupIds.toSet().containsAll({divB, divC})), isTrue);
      expect(ce.first.officialCode, '702CO0E034');
      expect(ce.every((e) => e.startTime == '10:00' && e.endTime == '13:00' && e.timeSource == 'page default'), isTrue);
      // No exam is invented for MAD (not listed in the source).
      expect(ce.any((e) => e.subjectCode == 'MAD'), isFalse);
    });

    test('Cell-specific times override the page default', () {
      final dw = data.exams.firstWhere((e) => e.officialCode == '702DB0C036');
      expect((dw.startTime, dw.endTime, dw.timeSource), ('14:00', '17:00', 'cell'));
      final bs = data.exams.firstWhere((e) => e.officialCode == '702TG0C024');
      expect((bs.startTime, bs.endTime), ('10:00', '12:00'));
    });

    test('Open-elective exams link to offerings; spelling differences are flagged, not silent', () {
      final g = data.exams.firstWhere((e) => e.subjectName == '5G for Everyone');
      expect(formatDate(g.date), '2026-12-02');
      expect(g.electiveOfferingIds, ['oe1-01']);
      final w = data.exams.firstWhere((e) => e.subjectName == 'Wireless Communications for Everybody');
      expect(w.reviewFlags.single, contains('Wireless Communication for Everybody'));
      expect(w.startTime, '14:00');
    });

    test('Imported data passes validation (no errors); unlinked streams are warnings', () {
      final r = check(data, data.exams);
      expect(r.errors, isEmpty);
      expect(r.warnings.where((w) => w.contains('Not linked')).length, 83); // 88 core rows - 5 linked
    });
  });

  group('Exam validation', () {
    final d17 = DateTime(2026, 11, 17);
    test('Duplicate subject/date for the same students is an error', () {
      expect(
        check(data, [
          exam('a', 'OR', d17),
          exam('b', 'OR', d17, groups: [divB, divC]),
        ]).errors.join(),
        contains('Duplicate'),
      );
    });
    test('Overlapping exams for the same group clash; different groups do not', () {
      expect(check(data, [exam('a', 'OR', d17), exam('b', 'AI', d17, start: '12:00', end: '15:00')]).errors.join(), contains('Clashes'));
      expect(
        check(data, [
          exam('a', 'OR', d17),
          exam('b', 'AI', d17, groups: [divC]),
        ]).errors,
        isEmpty,
      );
      expect(check(data, [exam('a', 'OR', d17), exam('b', 'AI', d17, start: '14:00', end: '17:00')]).errors, isEmpty);
    });
    test('Bad times, unknown groups and out-of-window dates are reported', () {
      final r = check(data, [
        exam('a', 'OR', d17, start: '13:00', end: '10:00'),
        exam('b', 'AI', DateTime(2026, 11, 18), groups: ['ghost']),
        exam('c', 'SE', DateTime(2027, 1, 5)),
        exam('d', 'OS', DateTime(2026, 11, 20), start: '9am'),
      ]);
      expect(r.errors.join(' '), allOf(contains('End time'), contains('Unknown academic group'), contains('HH:MM')));
      expect(r.warnings.join(' '), contains('outside the Term End Exam window'));
    });
    test('Regression: a NEW exam duplicating/clashing with an IMPORTED one is blocked on the new record', () {
      final w = data.termEndExamWindow!;
      validationFor(List<Exam> xs) => validateExams(
        xs,
        groupIds: data.groups.map((g) => g.id).toSet(),
        electiveIds: data.electives.map((e) => e.id).toSet(),
        windowStart: w.start,
        windowEnd: w.end,
      );
      final imported = data.exams.firstWhere((e) => e.groupIds.contains(divB) && e.subjectCode == 'OR'); // has officialCode
      final dup = exam('new-dup', 'OR', imported.date); // admin-entered: no officialCode
      final clash = exam('new-clash', 'MAD', imported.date, start: '11:00', end: '12:00');
      final r1 = validationFor([imported, dup]);
      expect(r1.errors.where((e) => e.entryId == 'new-dup').single.message, contains('Duplicate'));
      final r2 = validationFor([imported, clash]);
      expect(r2.errors.where((e) => e.entryId == 'new-clash').single.message, contains('Clashes with Operations Research'));
    });

    test('Withdrawn (archived) exams are ignored for duplicate checks', () {
      final withdrawn = exam('a', 'OR', d17).copyWith(status: PublishStatus.archived);
      expect(check(data, [withdrawn, exam('b', 'OR', d17)]).errors, isEmpty);
    });
  });

  group('Student visibility', () {
    Future<AppState> state() async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(repo: DemoRepository(seed()), auth: null, cache: await LocalCache.open(), notifications: NotificationService());
      await s.init();
      return s;
    }

    test('Students see their group exams plus exams of chosen electives only', () async {
      final s = await state();
      await s.chooseDemoProfile(groupId: divC, batch: 'C1');
      expect(s.myExams.map((e) => e.subjectCode).toList(), ['OR', 'AI', 'SE', 'OS', 'IVP']);
      expect(s.unchosenElectiveSlots, ['OE-1', 'OE-2']);
      await s.updatePreferences({'oe1OfferingId': 'oe1-01', 'oe2OfferingId': 'oe2-02'}); // 5G; Quantum Computing
      expect(s.myExams.map((e) => e.subjectName).skip(5), ['5G for Everyone', 'Quantum Computing and Technologies']);
      expect(s.unchosenElectiveSlots, isEmpty);
    });

    test('Draft and withdrawn exams never reach students; republishing restores them', () async {
      final repo = DemoRepository(seed());
      final os = (await repo.fetch(asAdmin: true)).exams.firstWhere((e) => e.groupIds.contains(divB) && e.subjectCode == 'OS');
      await repo.saveExam(os.copyWith(status: PublishStatus.archived), actor);
      expect((await repo.fetch(asAdmin: false)).exams.any((e) => e.id == os.id), isFalse);
      expect((await repo.fetch(asAdmin: true)).exams.firstWhere((e) => e.id == os.id).status, PublishStatus.archived);
      await repo.saveExam(os.copyWith(status: PublishStatus.draft), actor);
      expect((await repo.fetch(asAdmin: false)).exams.any((e) => e.id == os.id), isFalse);
      await repo.saveExam(os.copyWith(status: PublishStatus.published), actor);
      expect((await repo.fetch(asAdmin: false)).exams.any((e) => e.id == os.id), isTrue);
      expect((await repo.listAudit()).first.action, 'exam.save');
    });

    test('Exam reminders are planned the evening before each of the student\'s exams', () async {
      final s = await state();
      await s.chooseDemoProfile(groupId: divB, batch: 'B1');
      final r = planReminders(now: DateTime(2026, 11, 1), exams: s.myExams, examReminders: true);
      expect(r.map((x) => x.at), [
        DateTime(2026, 11, 16, 18),
        DateTime(2026, 11, 18, 18),
        DateTime(2026, 11, 22, 18),
        DateTime(2026, 11, 24, 18),
        DateTime(2026, 11, 26, 18),
      ]);
      expect(r.first.body, 'Starts at 10:00');
    });
  });
}
