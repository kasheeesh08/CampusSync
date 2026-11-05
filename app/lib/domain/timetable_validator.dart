import 'models.dart';

enum IssueLevel { error, warning }

class ValidationIssue {
  final IssueLevel level;
  final String message;
  final String? entryId;
  const ValidationIssue(this.level, this.message, [this.entryId]);
  @override
  String toString() => '${level.name.toUpperCase()}${entryId != null ? ' [$entryId]' : ''}: $message';
}

class ValidationResult {
  final List<ValidationIssue> issues;
  const ValidationResult(this.issues);
  List<ValidationIssue> get errors => issues.where((i) => i.level == IssueLevel.error).toList();
  List<ValidationIssue> get warnings => issues.where((i) => i.level == IssueLevel.warning).toList();

  /// Malformed data is never publishable; warnings need admin acknowledgement.
  bool get canPublish => errors.isEmpty;
}

/// Validates a timetable version before it can be published.
class TimetableValidator {
  final Map<String, Room> rooms;
  final Set<String> subjectCodes;
  final Set<String> facultyIds;
  final CampusSettings settings;

  TimetableValidator({
    required Iterable<Room> rooms,
    required Iterable<String> subjectCodes,
    required Iterable<String> facultyIds,
    this.settings = const CampusSettings(),
  }) : rooms = {for (final r in rooms) r.id: r},
       subjectCodes = subjectCodes.toSet(),
       facultyIds = facultyIds.toSet();

  ValidationResult validate(
    TimetableVersion version, {
    required AcademicGroup? group,
    Iterable<TimetableVersion> otherPublished = const [],
    Map<String, AcademicGroup> groupsById = const {},
  }) {
    final issues = <ValidationIssue>[];
    void err(String m, [String? id]) => issues.add(ValidationIssue(IssueLevel.error, m, id));
    void warn(String m, [String? id]) => issues.add(ValidationIssue(IssueLevel.warning, m, id));

    if (group == null) {
      err('Academic group "${version.groupId}" does not exist.');
    } else if (!group.active) {
      warn('Academic group "${group.label}" is inactive; its timetable will be ignored.');
    }
    final to = version.effectiveTo;
    if (to != null && to.isBefore(version.effectiveFrom)) {
      err('Effective end date is before the start date.');
    }
    if (version.entries.isEmpty) err('Timetable has no entries.');

    final seenIds = <String>{};
    final active = <TimetableEntry>[];
    for (final e in version.entries) {
      if (!seenIds.add(e.id)) err('Duplicate entry id.', e.id);
      if (e.weekday < 1 || e.weekday > 7) err('Weekday must be 1 (Mon) to 7 (Sun).', e.id);
      if (e.endMin <= e.startMin) {
        err('End time ${formatHm(e.endMin)} is not after start time ${formatHm(e.startMin)}.', e.id);
        continue;
      }
      if (e.startMin < settings.dayStartMin || e.endMin > settings.dayEndMin) {
        warn(
          'Entry ${formatHm(e.startMin)}-${formatHm(e.endMin)} is outside campus hours '
          '${formatHm(settings.dayStartMin)}-${formatHm(settings.dayEndMin)}.',
          e.id,
        );
      }
      if (e.durationMin > 4 * 60) warn('Unusually long session (${e.durationMin} min).', e.id);
      if (e.kind.needsRoom) {
        if (e.subjectCode == null || e.subjectCode!.isEmpty) {
          err('Subject is required for ${e.kind.wire} entries.', e.id);
        } else if (!subjectCodes.contains(e.subjectCode) && e.electiveOfferingId == null) {
          err('Unknown subject code "${e.subjectCode}".', e.id);
        }
        if (e.roomId == null) {
          warn('No room assigned.', e.id);
        } else if (!rooms.containsKey(e.roomId)) {
          err('Unknown room "${e.roomId}".', e.id);
        } else if (!rooms[e.roomId]!.active) {
          warn('Room ${e.roomId} is inactive.', e.id);
        }
        if (e.facultyId != null && !facultyIds.contains(e.facultyId)) {
          err('Unknown faculty "${e.facultyId}".', e.id);
        }
      }
      if (e.batch != null && group != null && group.batches.isNotEmpty && !group.batches.contains(e.batch)) {
        err('Batch "${e.batch}" is not defined for ${group.label}.', e.id);
      }
      if (e.reviewFlags.isNotEmpty) warn('Flagged for review: ${e.reviewFlags.join(' ')}', e.id);
      if (!e.cancelled) active.add(e);
    }

    // Intra-version clashes.
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        final a = active[i], b = active[j];
        if (a.weekday != b.weekday || !a.overlaps(b.startMin, b.endMin)) continue;
        final when = '${weekdayShort[a.weekday - 1]} ${formatHm(a.startMin)}';
        if (a.roomId != null && a.roomId == b.roomId) {
          err('Room ${a.roomId} double-booked with ${b.id} on $when.', a.id);
        }
        if (a.facultyId != null && a.facultyId == b.facultyId) {
          warn('Faculty ${a.facultyInitials ?? a.facultyId} double-booked with ${b.id} on $when.', a.id);
        }
        final batchClash = a.batch == null || b.batch == null || a.batch == b.batch;
        if (batchClash && a.electiveOfferingId == null && b.electiveOfferingId == null) {
          err(
            'Overlapping sessions for the same students (${a.batch ?? 'whole division'} / '
            '${b.batch ?? 'whole division'}) with ${b.id} on $when.',
            a.id,
          );
        }
      }
    }

    // Clashes with other groups' published timetables.
    for (final other in otherPublished) {
      if (other.groupId == version.groupId) continue;
      if (!_rangesOverlap(version, other)) continue;
      final label = groupsById[other.groupId]?.label ?? other.groupId;
      for (final a in active) {
        if (a.roomId == null) continue;
        for (final b in other.entries) {
          if (b.cancelled || b.roomId != a.roomId || b.weekday != a.weekday) continue;
          if (!a.overlaps(b.startMin, b.endMin)) continue;
          if (a.sharedNote != null && b.sharedNote != null) continue; // declared combined session
          warn(
            'Room ${a.roomId} is also used by $label (${b.subjectCode ?? ''}) on '
            '${weekdayShort[a.weekday - 1]} ${formatHm(b.startMin)}-${formatHm(b.endMin)}.',
            a.id,
          );
        }
      }
    }
    return ValidationResult(issues);
  }

  static bool _rangesOverlap(TimetableVersion a, TimetableVersion b) {
    final aEnd = a.effectiveTo ?? DateTime(9999);
    final bEnd = b.effectiveTo ?? DateTime(9999);
    return !a.effectiveFrom.isAfter(bEnd) && !b.effectiveFrom.isAfter(aEnd);
  }
}
