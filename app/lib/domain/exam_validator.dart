import 'models.dart';
import 'timetable_validator.dart' show IssueLevel, ValidationIssue, ValidationResult;

/// Validates examination records before (re)publication.
///
/// Errors block publishing; warnings need review (e.g. unlinked records that
/// no student will see, or dates outside the Term End Exam window).
ValidationResult validateExams(
  List<Exam> exams, {
  required Set<String> groupIds,
  required Set<String> electiveIds,
  DateTime? windowStart,
  DateTime? windowEnd,
}) {
  final issues = <ValidationIssue>[];
  void err(String m, String id) => issues.add(ValidationIssue(IssueLevel.error, m, id));
  void warn(String m, String id) => issues.add(ValidationIssue(IssueLevel.warning, m, id));

  final ids = <String>{};
  for (final e in exams) {
    if (!ids.add(e.id)) err('Duplicate exam id.', e.id);
    int? s, en;
    try {
      s = e.startMin;
      en = e.endMin;
    } on FormatException catch (x) {
      err(x.message, e.id);
    }
    if (s != null && en != null && en <= s) err('End time is not after start time.', e.id);
    if ((s == null) != (en == null)) warn('Only one of start/end time is set.', e.id);
    for (final g in e.groupIds) {
      if (!groupIds.contains(g)) err('Unknown academic group "$g".', e.id);
    }
    for (final o in e.electiveOfferingIds) {
      if (!electiveIds.contains(o)) err('Unknown elective offering "$o".', e.id);
    }
    if (e.groupIds.isEmpty && e.electiveOfferingIds.isEmpty) {
      warn('Not linked to any group or elective; no student will see it.', e.id);
    }
    if (windowStart != null && e.date.isBefore(windowStart) || windowEnd != null && e.date.isAfter(windowEnd)) {
      warn('Date ${formatDate(e.date)} is outside the Term End Exam window.', e.id);
    }
    if (e.reviewFlags.isNotEmpty) warn('Review: ${e.reviewFlags.join(' ')}', e.id);
  }

  // Duplicates and clashes among records that are (or will be) visible.
  final live = exams.where((e) => e.status != PublishStatus.archived).toList();
  for (var i = 0; i < live.length; i++) {
    for (var j = i + 1; j < live.length; j++) {
      final a = live[i], b = live[j];
      if (a.date != b.date) continue;
      final shared =
          a.groupIds.toSet().intersection(b.groupIds.toSet()).isNotEmpty ||
          a.electiveOfferingIds.toSet().intersection(b.electiveOfferingIds.toSet()).isNotEmpty;
      if (!shared) continue;
      final sameSubject = a.subjectCode == b.subjectCode || (a.officialCode != null && a.officialCode == b.officialCode);
      if (sameSubject) {
        // Reported on both records so whichever one is being saved is blocked.
        err('Duplicate of ${b.id} (same subject, date and students).', a.id);
        err('Duplicate of ${a.id} (same subject, date and students).', b.id);
        continue;
      }
      final as = a.startMin, ae = a.endMin, bs = b.startMin, be = b.endMin;
      if (as == null || ae == null || bs == null || be == null || (as < be && bs < ae)) {
        err('Clashes with ${b.subjectName} (${b.id}) for the same students on ${formatDate(a.date)}.', a.id);
        err('Clashes with ${a.subjectName} (${a.id}) for the same students on ${formatDate(a.date)}.', b.id);
      }
    }
  }
  return ValidationResult(issues);
}
