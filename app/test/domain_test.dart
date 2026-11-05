import 'dart:convert';
import 'dart:io';

import 'package:campussync/data/campus_data.dart';
import 'package:campussync/domain/availability.dart';
import 'package:campussync/domain/models.dart';
import 'package:campussync/domain/schedule.dart';
import 'package:campussync/domain/timetable_import.dart';
import 'package:campussync/domain/timetable_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const divB = 'btech-computer-2026-27-sem5-div-b';
const divC = 'btech-computer-2026-27-sem5-div-c';

CampusData loadSeed() {
  final seed = <String, dynamic>{};
  for (final f in Directory('assets/seed').listSync().whereType<File>()) {
    seed[f.uri.pathSegments.last.replaceAll('.json', '')] = jsonDecode(f.readAsStringSync());
  }
  return CampusData.fromSeed(seed);
}

// Monday 20 July 2026 falls inside the published effective range.
final monday = DateTime(2026, 7, 20);
final wednesday = DateTime(2026, 7, 22);
final thursday = DateTime(2026, 7, 23);

Room room(String id, {bool active = true, bool bookable = true}) =>
    Room(id: id, code: id, name: id, type: 'classroom', floorId: '4', active: active, bookable: bookable);

TimetableEntry entry(
  String id,
  int weekday,
  String s,
  String e,
  String? roomId, {
  String? batch,
  bool cancelled = false,
  String subject = 'SE',
}) => TimetableEntry(
  id: id,
  weekday: weekday,
  startMin: parseHm(s),
  endMin: parseHm(e),
  kind: EntryKind.lecture,
  subjectCode: subject,
  roomId: roomId,
  batch: batch,
  cancelled: cancelled,
);

AcademicGroup grp(String id, {bool active = true}) =>
    AcademicGroup(id: id, type: 'division', academicYearId: 'y', semester: 5, label: id, active: active, batches: const ['X1', 'X2']);

TimetableVersion version(String groupId, List<TimetableEntry> entries, {int v = 1, VersionStatus status = VersionStatus.published}) =>
    TimetableVersion(
      id: '$groupId-v$v',
      groupId: groupId,
      version: v,
      status: status,
      effectiveFrom: DateTime(2026, 7, 13),
      effectiveTo: DateTime(2026, 11, 5),
      entries: entries,
    );

void main() {
  group('Seed data integrity', () {
    final data = loadSeed();

    test('Div B and Div C have separate published timetables', () {
      final b = data.availability.effectiveVersion(divB, monday)!;
      final c = data.availability.effectiveVersion(divC, monday)!;
      expect(b.groupId, divB);
      expect(c.groupId, divC);
      // Monday 08:00 differs: Div B has SE/IVP labs, Div C has MAD in CR-407.
      final b8 = b.entries.where((e) => e.weekday == 1 && e.startMin == 480).map((e) => e.subjectCode).toSet();
      final c8 = c.entries.where((e) => e.weekday == 1 && e.startMin == 480).map((e) => e.subjectCode).toSet();
      expect(b8, {'SE', 'IVP'});
      expect(c8, {'MAD'});
    });

    test('Every seeded timetable references known rooms, subjects and faculty', () {
      final validator = TimetableValidator(
        rooms: data.rooms,
        subjectCodes: data.subjects.map((s) => s.code),
        facultyIds: data.faculty.map((f) => f.id),
        settings: data.settings,
      );
      for (final v in data.versions) {
        final result = validator.validate(v, group: data.groupsById[v.groupId]);
        expect(result.errors, isEmpty, reason: '${v.id}: ${result.errors}');
      }
    });

    test('Validator surfaces the source cross-division overlaps as warnings', () {
      final validator = TimetableValidator(
        rooms: data.rooms,
        subjectCodes: data.subjects.map((s) => s.code),
        facultyIds: data.faculty.map((f) => f.id),
      );
      final b = data.versions.firstWhere((v) => v.groupId == divB);
      final others = data.versions.where((v) => v.groupId != divB);
      final w = validator.validate(b, group: data.groupsById[divB], otherPublished: others).warnings;
      expect(w.any((i) => i.message.contains('CR-405')), isTrue);
      // The declared combined B2+C2 MAD lab must not be reported.
      expect(w.any((i) => i.message.contains('CL-503') && i.message.contains('MAD') && i.entryId == 'b-18'), isFalse);
    });

    test('Floor 2 is integrated from its layout image without duplicate room ids', () {
      final f2 = data.floors.firstWhere((f) => f.id == '2');
      expect(f2.missingLayout, isFalse);
      final ids = data.rooms.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      final f2Rooms = data.rooms.where((r) => r.floorId == '2').map((r) => r.id).toSet();
      expect(f2Rooms, containsAll(['TR-201', 'TR-202', 'TR-203', 'CR-201', 'CR-204', 'CR-206', 'CR-209', 'CC-201', 'LAB-PHYSICS-LAB']));
      expect(f2Rooms, hasLength(13));
      // A floor-plan room with no timetable use is never reported as free.
      expect(data.availability.check('CR-201', monday, 600, 660).status, RoomStatus.noKnownClass);
    });

    test('Announcements are drafts until details are supplied', () {
      expect(data.announcements, hasLength(3));
      expect(data.announcements.every((a) => a.status == PublishStatus.draft), isTrue);
    });
  });

  group('Availability engine', () {
    final data = loadSeed();
    final engine = data.availability;

    test('Occupied: CR-402 Monday 10:00-11:00 is Div B Software Engineering', () {
      final r = engine.check('CR-402', monday, parseHm('10:00'), parseHm('11:00'));
      expect(r.status, RoomStatus.occupied);
      expect(r.conflicts.single.entry.subjectCode, 'SE');
      expect(r.conflicts.single.group.id, divB);
    });

    test('Known free interval is reported as partial coverage, not confirmed free', () {
      final r = engine.check('CR-402', monday, parseHm('12:00'), parseHm('13:00'));
      expect(r.status, RoomStatus.noKnownClass);
      expect(r.coverage.isComplete, isFalse);
      expect(r.freeIntervals, contains(const FreeInterval(720, 840)));
    });

    test('Boundary: a class ending at 11:00 does not block 11:00-12:00 unless another starts', () {
      final e = AvailabilityEngine(
        rooms: [room('R1')],
        groups: [grp('g')],
        versions: [
          version('g', [entry('a', 1, '10:00', '11:00', 'R1')]),
        ],
        settings: const CampusSettings(coverageDeclaredComplete: true),
      );
      expect(e.check('R1', monday, 660, 720).status, RoomStatus.freeVerified);
      expect(e.check('R1', monday, 659, 720).status, RoomStatus.occupied);
      expect(e.check('R1', monday, 540, 600).nextUse!.entry.id, 'a');
    });

    test('Overlapping classes of different durations are all reported', () {
      final e = AvailabilityEngine(
        rooms: [room('R1')],
        groups: [grp('g1'), grp('g2')],
        versions: [
          version('g1', [entry('lab', 1, '10:00', '12:00', 'R1')]),
          version('g2', [entry('lec', 1, '11:00', '12:00', 'R1')]),
        ],
      );
      final r = e.check('R1', monday, parseHm('11:30'), parseHm('12:30'));
      expect(r.status, RoomStatus.occupied);
      expect(r.conflicts.map((c) => c.entry.id).toSet(), {'lab', 'lec'});
    });

    test('Cancelled entries and break/library rows do not occupy rooms', () {
      final e = AvailabilityEngine(
        rooms: [room('R1')],
        groups: [grp('g')],
        versions: [
          version('g', [entry('c', 1, '10:00', '11:00', 'R1', cancelled: true)]),
        ],
        settings: const CampusSettings(coverageDeclaredComplete: true),
      );
      expect(e.check('R1', monday, 600, 660).status, RoomStatus.freeVerified);
    });

    test('Missing and inactive room records are not reported as free', () {
      final e = AvailabilityEngine(
        rooms: [room('OFF', active: false), room('LIB', bookable: false)],
        groups: [grp('g')],
        versions: [version('g', [])],
        settings: const CampusSettings(coverageDeclaredComplete: true),
      );
      expect(e.check('NOPE', monday, 600, 660).status, RoomStatus.unknownRoom);
      expect(e.check('OFF', monday, 600, 660).status, RoomStatus.unavailable);
      expect(e.check('LIB', monday, 600, 660).status, RoomStatus.unavailable);
    });

    test('Incomplete coverage: an active group without a published timetable blocks verification', () {
      final e = AvailabilityEngine(
        rooms: [room('R1')],
        groups: [grp('g1'), grp('g2')],
        versions: [version('g1', [])],
        settings: const CampusSettings(coverageDeclaredComplete: true),
      );
      final r = e.check('R1', monday, 600, 660);
      expect(r.status, RoomStatus.noKnownClass);
      expect(r.coverage.missing.single.id, 'g2');
    });

    test('Newly published timetable changes previously calculated availability', () {
      final versions = [version('g1', [])];
      final groups = [grp('g1')];
      var e = AvailabilityEngine(rooms: [room('R1')], groups: groups, versions: versions);
      expect(e.check('R1', monday, 600, 660).status, RoomStatus.noKnownClass);
      versions.add(version('g2', [entry('n', 1, '10:00', '11:00', 'R1')]));
      groups.add(grp('g2'));
      e = AvailabilityEngine(rooms: [room('R1')], groups: groups, versions: versions);
      expect(e.check('R1', monday, 600, 660).status, RoomStatus.occupied);
    });

    test('Timetable revision: highest published version wins; drafts are ignored', () {
      final e = AvailabilityEngine(
        rooms: [room('R1'), room('R2')],
        groups: [grp('g')],
        versions: [
          version('g', [entry('old', 1, '10:00', '11:00', 'R1')], v: 1),
          version('g', [entry('new', 1, '10:00', '11:00', 'R2')], v: 2),
          version('g', [entry('draft', 1, '10:00', '11:00', 'R1')], v: 3, status: VersionStatus.draft),
        ],
      );
      expect(e.check('R1', monday, 600, 660).status, RoomStatus.noKnownClass);
      expect(e.check('R2', monday, 600, 660).status, RoomStatus.occupied);
    });

    test('Dates outside the effective range have no coverage', () {
      final r = engine.check('CR-402', DateTime(2026, 12, 14), 600, 660);
      expect(r.status, RoomStatus.noKnownClass);
      expect(r.coverage.published, isEmpty);
    });

    test('Invalid interval is rejected', () {
      expect(() => engine.check('CR-402', monday, 660, 600), throwsArgumentError);
    });
  });

  group('Personal schedule', () {
    final data = loadSeed();
    final svc = ScheduleService(
      data.availability,
      settings: data.settings,
      electivePoolBySlot: const {'OE-1': 'oe1-2026-27-odd', 'OE-2': 'oe2-2026-27-odd'},
    );

    test('Batch filter: B1 sees SE lab, B2 sees IVP lab on Monday 08:00', () {
      final b1 = svc.entriesOn(const ScheduleProfile(groupId: divB, batch: 'B1'), monday);
      final b2 = svc.entriesOn(const ScheduleProfile(groupId: divB, batch: 'B2'), monday);
      expect(b1.first.subjectCode, 'SE');
      expect(b2.first.subjectCode, 'IVP');
    });

    test('Free periods and empty source slots are distinguished', () {
      final slots = svc.dayView(const ScheduleProfile(groupId: divB, batch: 'B1'), thursday);
      expect(slots.first.type, SlotType.noEntry); // Thu 08-12 is blank in the source
      expect(slots.any((s) => s.type == SlotType.freePeriod && s.entry!.kind == EntryKind.breakPeriod), isTrue);
    });

    test('Chosen OE-I offering replaces the generic elective block', () {
      final generic = svc.entriesOn(const ScheduleProfile(groupId: divC, batch: 'C1'), wednesday).last;
      expect(generic.kind, EntryKind.elective);
      final picked = svc.entriesOn(
        const ScheduleProfile(groupId: divC, batch: 'C1', oe1OfferingId: 'oe1-01'),
        wednesday,
      ); // 5G for Everyone
      expect(picked.last.subjectName, '5G for Everyone');
      expect(picked.last.kind, EntryKind.lab);
    });

    test('Unknown group gets no substituted timetable', () {
      final slots = svc.dayView(const ScheduleProfile(groupId: 'unpublished-group'), monday);
      expect(slots.single.type, SlotType.noTimetable);
    });

    test('Next class skips finished classes and breaks', () {
      final n = svc.nextClass(const ScheduleProfile(groupId: divB, batch: 'B1'), DateTime(2026, 7, 20, 12, 10))!;
      expect(n.entry.subjectCode, 'AI'); // 12-13 break, 13-14 library, 14:00 AI
      expect(n.inProgress, isFalse);
    });
  });

  group('Validation and import', () {
    final data = loadSeed();
    final validator = TimetableValidator(
      rooms: data.rooms,
      subjectCodes: data.subjects.map((s) => s.code),
      facultyIds: data.faculty.map((f) => f.id),
    );
    final importer = TimetableImporter(rooms: data.rooms, faculty: data.faculty);

    test('Valid CSV imports and resolves room aliases and faculty initials', () {
      final r = importer.parseCsv(
        'weekday,start,end,kind,subject,faculty,room,batch\n'
        'Mon,08:00,10:00,lab,SE,PRK,E. CL 401,X1\n'
        'Tue,10:00,11:00,lecture,AI,ANA,BC Lab,\n',
      );
      expect(r.errors, isEmpty);
      expect(r.entries[0].roomId, 'CL-401');
      expect(r.entries[0].facultyId, 'fac-prashasti-kanikar');
      expect(r.entries[1].roomId, 'LAB-BASIC-COMMUNICATION-LAB');
    });

    test('CSV with bad rows reports line-level errors', () {
      final r = importer.parseCsv(
        'weekday,start,end,kind,subject,faculty,room\n'
        'Funday,08:00,10:00,lab,SE,PRK,CL 401\n'
        'Mon,11:00,10:00,lecture,SE,,CR 402\n'
        'Mon,25:00,26:00,lecture,SE,,CR 402\n'
        'Mon,08:00,09:00,lecture,SE,XYZ,CR 999\n',
      );
      expect(r.entries, isEmpty);
      expect(r.errors, hasLength(4));
      expect(r.errors[0], contains('invalid weekday'));
      expect(r.errors[1], contains('end time must be after start time'));
      expect(r.errors[3], allOf(contains('unknown room'), contains('unknown faculty')));
    });

    test('Uploaded files: unsupported types and empty files are rejected; .csv/.json are parsed', () {
      expect(importer.parseFile('timetable.pdf', 'x').errors.single, contains('Unsupported file type'));
      expect(importer.parseFile('notes.txt', 'weekday,start').errors.single, contains('Unsupported file type'));
      expect(importer.parseFile('empty.csv', '  ').errors.single, contains('is empty'));
      final csv = importer.parseFile('Div-B.CSV', 'weekday,start,end,kind,subject,faculty,room\nMon,08:00,09:00,lecture,SE,PRK,CR 201\n');
      expect(csv.ok, isTrue);
      expect(csv.entries.single.roomId, 'CR-201');
      expect(importer.parseFile('v.json', '{"entries": 5}').errors.single, contains('must be a list'));
    });

    test('CSV missing required columns is rejected', () {
      expect(importer.parseCsv('day,from,to\nMon,8,9').errors.single, contains('Missing column'));
    });

    test('Validator blocks double-booked rooms and unknown references', () {
      final v = version(divB, [
        entry('x1', 1, '10:00', '11:00', 'CR-402', batch: 'B1'),
        entry('x2', 1, '10:30', '11:30', 'CR-402', batch: 'B2'),
        entry('x3', 2, '10:00', '11:00', 'CR-999', subject: 'NOPE'),
      ]);
      final r = validator.validate(v, group: data.groupsById[divB]);
      expect(r.canPublish, isFalse);
      expect(
        r.errors.map((e) => e.message).join(' '),
        allOf(contains('double-booked'), contains('Unknown room'), contains('Unknown subject')),
      );
    });

    test('Validator rejects empty timetables and reversed effective dates', () {
      final v = TimetableVersion(
        id: 'v',
        groupId: divB,
        version: 1,
        status: VersionStatus.draft,
        effectiveFrom: DateTime(2026, 8, 1),
        effectiveTo: DateTime(2026, 7, 1),
      );
      final r = validator.validate(v, group: data.groupsById[divB]);
      expect(r.errors.map((e) => e.message), containsAll(['Timetable has no entries.', 'Effective end date is before the start date.']));
    });

    test('Overlapping sessions for the same batch are errors; different batches are fine', () {
      final ok = validator.validate(
        version(divB, [entry('p', 1, '08:00', '10:00', 'CL-401', batch: 'B1'), entry('q', 1, '08:00', '10:00', 'CL-503', batch: 'B2')]),
        group: data.groupsById[divB],
      );
      expect(ok.errors, isEmpty);
      final bad = validator.validate(
        version(divB, [entry('p', 1, '08:00', '10:00', 'CL-401', batch: 'B1'), entry('q', 1, '09:00', '10:00', 'CL-503')]),
        group: data.groupsById[divB],
      );
      expect(bad.errors.single.message, contains('same students'));
    });
  });

  group('Time helpers', () {
    test('parseHm boundaries', () {
      expect(parseHm('00:00'), 0);
      expect(parseHm('23:59'), 1439);
      expect(() => parseHm('24:00'), throwsFormatException);
      expect(() => parseHm('8am'), throwsFormatException);
      expect(formatHm12(780), '1:00 PM');
      expect(formatHm12(0), '12:00 AM');
    });

    test('Announcement timing', () {
      final a = Announcement(id: 'a', title: 't', startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31));
      expect(a.timing(DateTime(2026, 9, 30)), 'upcoming');
      expect(a.timing(DateTime(2026, 10, 31, 23)), 'ongoing');
      expect(a.timing(DateTime(2026, 11, 1)), 'expired');
    });
  });
}
