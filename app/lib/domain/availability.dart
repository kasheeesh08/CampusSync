import 'models.dart';

/// Result category for a room over a requested interval.
enum RoomStatus {
  /// At least one published, non-cancelled entry overlaps the interval.
  occupied,

  /// No overlapping entry, and every active group's timetable is published and
  /// an administrator has declared campus coverage complete.
  freeVerified,

  /// No overlapping entry in the timetables we have, but coverage is partial,
  /// so the room is not confirmed free.
  noKnownClass,

  /// Room is inactive, not bookable, or restricted by an administrator.
  unavailable,

  /// The room id does not exist in the room registry.
  unknownRoom,
}

class ScheduledUse {
  final TimetableEntry entry;
  final AcademicGroup group;
  final TimetableVersion version;
  const ScheduledUse(this.entry, this.group, this.version);
}

class Coverage {
  final List<AcademicGroup> published;
  final List<AcademicGroup> missing;
  final bool declaredComplete;

  const Coverage({required this.published, required this.missing, required this.declaredComplete});

  int get activeCount => published.length + missing.length;
  bool get isComplete => declaredComplete && missing.isEmpty && published.isNotEmpty;

  String describe() {
    if (published.isEmpty) return 'No published timetable covers this date.';
    final base = '${published.length} of $activeCount registered group timetables are published for this date';
    if (!declaredComplete) return '$base; other departments that use these rooms are not yet covered.';
    if (missing.isNotEmpty) return '$base; missing: ${missing.map((g) => g.label).join(', ')}.';
    return 'All registered timetables are published for this date.';
  }
}

class FreeInterval {
  final int startMin;
  final int endMin;
  const FreeInterval(this.startMin, this.endMin);
  @override
  String toString() => '${formatHm(startMin)}-${formatHm(endMin)}';
  @override
  bool operator ==(Object other) => other is FreeInterval && other.startMin == startMin && other.endMin == endMin;
  @override
  int get hashCode => Object.hash(startMin, endMin);
}

class RoomAvailability {
  final String roomId;
  final Room? room;
  final RoomStatus status;
  final String reason;
  final List<ScheduledUse> conflicts;
  final ScheduledUse? nextUse;
  final List<FreeInterval> freeIntervals;
  final List<ScheduledUse> dayUses;
  final Coverage coverage;

  const RoomAvailability({
    required this.roomId,
    required this.room,
    required this.status,
    required this.reason,
    required this.conflicts,
    required this.nextUse,
    required this.freeIntervals,
    required this.dayUses,
    required this.coverage,
  });
}

/// Pure, UI-independent classroom availability engine.
///
/// It considers every *active* group that has a *published* timetable version
/// effective on the requested date, so newly published groups participate
/// automatically without code changes.
class AvailabilityEngine {
  final Map<String, Room> _rooms;
  final List<AcademicGroup> groups;
  final List<TimetableVersion> versions;
  final CampusSettings settings;

  AvailabilityEngine({required Iterable<Room> rooms, required this.groups, required this.versions, this.settings = const CampusSettings()})
    : _rooms = {for (final r in rooms) r.id: r};

  /// The version that applies to [group] on [date]: the highest published
  /// version number whose effective range contains the date.
  TimetableVersion? effectiveVersion(String groupId, DateTime date) {
    TimetableVersion? best;
    for (final v in versions) {
      if (v.groupId != groupId || v.status != VersionStatus.published || !v.coversDate(date)) continue;
      if (best == null || v.version > best.version) best = v;
    }
    return best;
  }

  Coverage coverageOn(DateTime date) {
    final published = <AcademicGroup>[];
    final missing = <AcademicGroup>[];
    for (final g in groups.where((g) => g.active)) {
      (effectiveVersion(g.id, date) != null ? published : missing).add(g);
    }
    return Coverage(published: published, missing: missing, declaredComplete: settings.coverageDeclaredComplete);
  }

  /// All room-bearing, non-cancelled uses on [date], sorted by start time.
  List<ScheduledUse> usesOn(DateTime date) {
    final out = <ScheduledUse>[];
    for (final g in groups.where((g) => g.active)) {
      final v = effectiveVersion(g.id, date);
      if (v == null) continue;
      for (final e in v.entries) {
        if (e.weekday != date.weekday || e.cancelled || e.roomId == null || e.kind.isFreePeriod) continue;
        out.add(ScheduledUse(e, g, v));
      }
    }
    out.sort((a, b) => a.entry.startMin.compareTo(b.entry.startMin));
    return out;
  }

  RoomAvailability check(String roomId, DateTime date, int startMin, int endMin, {List<ScheduledUse>? precomputed}) {
    if (endMin <= startMin) {
      throw ArgumentError('End time must be after start time (${formatHm(startMin)}-${formatHm(endMin)}).');
    }
    final coverage = coverageOn(date);
    final room = _rooms[roomId];
    final uses = (precomputed ?? usesOn(date)).where((u) => u.entry.roomId == roomId).toList();
    final conflicts = uses.where((u) => u.entry.overlaps(startMin, endMin)).toList();
    final next = uses.where((u) => u.entry.startMin >= endMin).firstOrNull;
    final free = _freeIntervals(uses);

    RoomStatus status;
    String reason;
    if (room == null) {
      status = RoomStatus.unknownRoom;
      reason = 'Room "$roomId" is not in the room registry.';
    } else if (!room.active) {
      status = RoomStatus.unavailable;
      reason = room.restrictionNote ?? 'Room is marked inactive by an administrator.';
    } else if (!room.bookable) {
      status = RoomStatus.unavailable;
      reason = room.restrictionNote ?? 'This space is not used for scheduled classes.';
    } else if (conflicts.isNotEmpty) {
      status = RoomStatus.occupied;
      final c = conflicts.first.entry;
      reason =
          'Scheduled: ${c.subjectName ?? c.subjectCode ?? 'class'} '
          '(${conflicts.first.group.label}${c.batch != null ? ' ${c.batch}' : ''}) '
          '${formatHm(c.startMin)}-${formatHm(c.endMin)}';
    } else if (coverage.isComplete) {
      status = RoomStatus.freeVerified;
      reason = 'Free according to all published timetables.';
    } else {
      status = RoomStatus.noKnownClass;
      reason = 'No class in the published timetables. ${coverage.describe()}';
    }

    return RoomAvailability(
      roomId: roomId,
      room: room,
      status: status,
      reason: reason,
      conflicts: conflicts,
      nextUse: next,
      freeIntervals: free,
      dayUses: uses,
      coverage: coverage,
    );
  }

  /// Checks every bookable room (or [roomIds]) for the interval.
  List<RoomAvailability> checkAll(DateTime date, int startMin, int endMin, {Iterable<String>? roomIds}) {
    final uses = usesOn(date);
    final ids = roomIds ?? _rooms.values.where((r) => r.bookable).map((r) => r.id);
    return [for (final id in ids) check(id, date, startMin, endMin, precomputed: uses)];
  }

  List<FreeInterval> _freeIntervals(List<ScheduledUse> roomUses) {
    final busy = roomUses.map((u) => (u.entry.startMin, u.entry.endMin)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
    final out = <FreeInterval>[];
    var cursor = settings.dayStartMin;
    for (final (s, e) in busy) {
      if (s > cursor) out.add(FreeInterval(cursor, s < settings.dayEndMin ? s : settings.dayEndMin));
      if (e > cursor) cursor = e;
      if (cursor >= settings.dayEndMin) break;
    }
    if (cursor < settings.dayEndMin) out.add(FreeInterval(cursor, settings.dayEndMin));
    return out.where((f) => f.endMin > f.startMin).toList();
  }
}
