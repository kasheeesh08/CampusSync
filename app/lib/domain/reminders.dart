import 'models.dart';
import 'schedule.dart';

class PlannedReminder {
  final String key; // stable identity, e.g. "class:b-02:2026-07-20"
  final String title;
  final String body;
  final DateTime at; // campus local time
  const PlannedReminder(this.key, this.title, this.body, this.at);
}

/// Pure reminder planning so it can be unit-tested and re-run whenever the
/// timetable, announcements or preferences change.
List<PlannedReminder> planReminders({
  required DateTime now,
  ScheduleService? schedule,
  ScheduleProfile? profile,
  String Function(TimetableEntry)? describe,
  bool classes = false,
  int leadMinutes = 10,
  List<Exam> exams = const [],
  bool examReminders = false,
  List<Announcement> deadlines = const [],
  bool deadlineReminders = false,
  int days = 7,
}) {
  final out = <PlannedReminder>[];
  if (classes && schedule != null && profile != null) {
    for (var d = 0; d < days; d++) {
      final date = dateOnly(now).add(Duration(days: d));
      for (final e in schedule.entriesOn(profile, date)) {
        if (e.kind.isFreePeriod) continue;
        final at = date.add(Duration(minutes: e.startMin - leadMinutes));
        if (!at.isAfter(now)) continue;
        final room = e.roomLabel ?? e.roomId;
        out.add(
          PlannedReminder(
            'class:${e.id}:${formatDate(date)}',
            describe?.call(e) ?? e.subjectCode ?? 'Class',
            'Starts at ${formatHm12(e.startMin)}${room != null ? ' in $room' : ''}',
            at,
          ),
        );
      }
    }
  }
  if (examReminders) {
    for (final x in exams) {
      // Evening before the exam, 6 pm, since many exam times are not specified.
      final at = x.date.subtract(const Duration(days: 1)).add(const Duration(hours: 18));
      if (at.isAfter(now)) {
        out.add(
          PlannedReminder(
            'exam:${x.id}',
            'Exam tomorrow: ${x.subjectName}',
            x.startTime != null ? 'Starts at ${x.startTime}' : 'Check the official timetable for timing.',
            at,
          ),
        );
      }
    }
  }
  if (deadlineReminders) {
    for (final a in deadlines) {
      final end = a.endDate;
      if (end == null || a.status != PublishStatus.published) continue;
      final at = end.subtract(const Duration(days: 1)).add(const Duration(hours: 9));
      if (at.isAfter(now)) {
        out.add(PlannedReminder('deadline:${a.id}:${formatDate(end)}', 'Deadline tomorrow', a.title, at));
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
