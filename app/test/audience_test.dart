import 'dart:convert';
import 'dart:io';

import 'package:campussync/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

// The key format must match studentAudience() in firebase/firestore.rules
// ("all", "group:<id>", "dept:<id>", "oe:<id>"); a mismatch would hide records.
void main() {
  const divB = 'btech-computer-2026-27-sem5-div-b';

  test('announcement audience keys', () {
    expect(const AnnouncementAudience().keys, ['all']);
    expect(const AnnouncementAudience(scope: 'groups', ids: [divB, 'g2']).keys, ['group:$divB', 'group:g2']);
    expect(const AnnouncementAudience(scope: 'department', ids: ['dept-ce']).keys, ['dept:dept-ce']);
    final json = Announcement(id: 'a', title: 'T', category: 'general', audience: const AnnouncementAudience(scope: 'groups', ids: [divB])).toJson();
    expect(json['audienceKeys'], ['group:$divB']);
  });

  test('exam audience keys list every group and elective (and are written to Firestore)', () {
    final seed = jsonDecode(File('assets/seed/exams.json').readAsStringSync()) as Map<String, dynamic>;
    for (final raw in (seed['exams'] as List).cast<Map<String, dynamic>>()) {
      final e = Exam.fromJson(raw);
      expect(e.audienceKeys.length, e.groupIds.length + e.electiveOfferingIds.length);
      expect(e.toJson()['audienceKeys'], e.audienceKeys);
      expect(e.audienceKeys, isNot(contains('all')));
    }
  });

  test('student audience keys: only present values, no duplicates', () {
    const p = StudentProfile(uid: 'u', email: 'e', displayName: 'D', sapId: '99999300001', rollNumber: 'B001', groupId: divB, oe1OfferingId: 'oe1-00');
    expect(studentAudienceKeys(p, 'dept-ce'), ['all', 'group:$divB', 'dept:dept-ce', 'oe:oe1-00']);
    expect(studentAudienceKeys(p, null), ['all', 'group:$divB', 'oe:oe1-00']);
    const same = StudentProfile(uid: 'u', email: 'e', displayName: 'D', sapId: '1', rollNumber: 'B001', groupId: divB, oe1OfferingId: 'x', oe2OfferingId: 'x');
    expect(studentAudienceKeys(same, null), ['all', 'group:$divB', 'oe:x']);
  });

  test('a student sees exactly the exams Exam.appliesTo selects (server filter == app filter)', () {
    final seed = jsonDecode(File('assets/seed/exams.json').readAsStringSync()) as Map<String, dynamic>;
    const p = StudentProfile(uid: 'u', email: 'e', displayName: 'D', sapId: '1', rollNumber: 'B001', groupId: divB, oe1OfferingId: 'oe1-00');
    final keys = studentAudienceKeys(p, 'dept-ce').toSet();
    for (final raw in (seed['exams'] as List).cast<Map<String, dynamic>>()) {
      final e = Exam.fromJson(raw);
      expect(e.audienceKeys.any(keys.contains), e.appliesTo(groupId: p.groupId, electiveIds: [p.oe1OfferingId, p.oe2OfferingId]), reason: e.id);
    }
  });
}
