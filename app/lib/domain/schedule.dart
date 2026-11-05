import 'availability.dart';
import 'models.dart';

enum SlotType { scheduled, freePeriod, elective, noEntry, noTimetable }

/// One row in a student's day view.
class DaySlot {
  final int startMin;
  final int endMin;
  final SlotType type;
  final TimetableEntry? entry;
  const DaySlot(this.startMin, this.endMin, this.type, [this.entry]);
}

/// The student's selection that personalises a group timetable.
class ScheduleProfile {
  final String groupId;
  final String? batch;
  final String? oe1OfferingId;
  final String? oe2OfferingId;
  const ScheduleProfile({required this.groupId, this.batch, this.oe1OfferingId, this.oe2OfferingId});
}

/// Builds a personalised schedule from published timetable versions.
///
/// Never substitutes another group's timetable: if the student's own group has
/// no published version for a date, the day is reported as [SlotType.noTimetable].
class ScheduleService {
  final AvailabilityEngine engine;
  final CampusSettings settings;
  final Map<String, String> electivePoolBySlot; // 'OE-1' -> elective pool group id

  ScheduleService(this.engine, {this.settings = const CampusSettings(), this.electivePoolBySlot = const {}});

  bool hasTimetable(ScheduleProfile p, DateTime date) => engine.effectiveVersion(p.groupId, date) != null;

  /// Entries for the student on [date] (batch-filtered, electives resolved).
  List<TimetableEntry> entriesOn(ScheduleProfile p, DateTime date) {
    final v = engine.effectiveVersion(p.groupId, date);
    if (v == null) return const [];
    final out = <TimetableEntry>[];
    for (final e in v.entries) {
      if (e.weekday != date.weekday || e.cancelled) continue;
      if (e.batch != null && p.batch != null && e.batch != p.batch) continue;
      if (e.kind == EntryKind.elective) {
        out.addAll(_resolveElective(e, p, date));
        continue;
      }
      out.add(e);
    }
    out.sort((a, b) => a.startMin != b.startMin ? a.startMin.compareTo(b.startMin) : (a.batch ?? '').compareTo(b.batch ?? ''));
    return out;
  }

  /// The division timetable blocks the whole elective window; once a student
  /// picks an offering we show that offering's actual sessions inside the window.
  List<TimetableEntry> _resolveElective(TimetableEntry slot, ScheduleProfile p, DateTime date) {
    final code = slot.subjectCode;
    final offeringId = code == 'OE-1' ? p.oe1OfferingId : (code == 'OE-2' ? p.oe2OfferingId : null);
    final poolId = electivePoolBySlot[code];
    if (offeringId == null || poolId == null) return [slot];
    final pool = engine.effectiveVersion(poolId, date);
    if (pool == null) return [slot];
    final sessions = pool.entries
        .where((e) => e.electiveOfferingId == offeringId && e.weekday == date.weekday && !e.cancelled)
        .where((e) => e.overlaps(slot.startMin, slot.endMin))
        .toList();
    // Multi-room offerings repeat a session per room; keep one per time.
    final seen = <String>{};
    final unique = [
      for (final s in sessions)
        if (seen.add('${s.startMin}-${s.endMin}')) s,
    ];
    return unique;
  }

  /// Day rows covering campus hours, with explicit "no entry" gaps.
  List<DaySlot> dayView(ScheduleProfile p, DateTime date) {
    if (!hasTimetable(p, date)) {
      return [DaySlot(settings.dayStartMin, settings.dayEndMin, SlotType.noTimetable)];
    }
    final entries = entriesOn(p, date);
    final out = <DaySlot>[];
    var cursor = settings.dayStartMin;
    for (final e in entries) {
      if (e.startMin > cursor) out.add(DaySlot(cursor, e.startMin, SlotType.noEntry));
      out.add(DaySlot(e.startMin, e.endMin, _typeOf(e), e));
      if (e.endMin > cursor) cursor = e.endMin;
    }
    if (cursor < settings.dayEndMin) out.add(DaySlot(cursor, settings.dayEndMin, SlotType.noEntry));
    return out;
  }

  static SlotType _typeOf(TimetableEntry e) =>
      e.kind.isFreePeriod ? SlotType.freePeriod : (e.kind == EntryKind.elective ? SlotType.elective : SlotType.scheduled);

  /// The class in progress or the next one within the following [lookaheadDays].
  ({TimetableEntry entry, DateTime start, bool inProgress})? nextClass(ScheduleProfile p, DateTime now, {int lookaheadDays = 7}) {
    final nowMin = now.hour * 60 + now.minute;
    for (var d = 0; d <= lookaheadDays; d++) {
      final date = dateOnly(now).add(Duration(days: d));
      for (final e in entriesOn(p, date)) {
        if (e.kind.isFreePeriod) continue;
        if (d == 0 && e.endMin <= nowMin) continue;
        final start = date.add(Duration(minutes: e.startMin));
        return (entry: e, start: start, inProgress: d == 0 && e.startMin <= nowMin);
      }
    }
    return null;
  }
}
