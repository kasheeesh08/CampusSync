/// Focus (study) sessions. Pure Dart: all time maths derives from wall-clock
/// timestamps, so a session stays correct across backgrounding, process death
/// and restarts — nothing depends on a ticking in-memory counter.
library;

enum FocusStatus { running, paused, completed, ended }

class FocusSession {
  final String id;
  final String spaceId; // e.g. 'library-f7'
  final String spotId; // e.g. 'desk-04'
  final int plannedMinutes;
  final DateTime startedAt;
  final Duration pausedTotal; // completed pauses only
  final DateTime? pausedAt; // set while paused
  final DateTime? finishedAt; // completion or early end time
  final FocusStatus status;

  const FocusSession({
    required this.id,
    required this.spaceId,
    required this.spotId,
    required this.plannedMinutes,
    required this.startedAt,
    this.pausedTotal = Duration.zero,
    this.pausedAt,
    this.finishedAt,
    this.status = FocusStatus.running,
  });

  static const allowedMinutes = [15, 25, 45, 60, 90];
  static const minMinutes = 5, maxMinutes = 180;

  Duration get planned => Duration(minutes: plannedMinutes);
  bool get isActive => status == FocusStatus.running || status == FocusStatus.paused;

  /// Time spent focusing (excludes pauses), capped at the planned length.
  Duration focusedAt(DateTime now) {
    final end = finishedAt ?? (status == FocusStatus.paused ? pausedAt! : now);
    final raw = end.difference(startedAt) - pausedTotal;
    if (raw.isNegative) return Duration.zero;
    return raw > planned ? planned : raw;
  }

  Duration remainingAt(DateTime now) => planned - focusedAt(now);

  /// When a running session will complete (null unless running).
  DateTime? get completesAt => status == FocusStatus.running ? startedAt.add(pausedTotal).add(planned) : null;

  /// Applies the clock: a running session whose time is up becomes completed
  /// at its exact completion moment (even if the app was closed then).
  FocusSession settle(DateTime now) {
    final due = completesAt;
    if (due != null && !now.isBefore(due)) {
      return _copy(status: FocusStatus.completed, finishedAt: due);
    }
    return this;
  }

  FocusSession pause(DateTime now) {
    final s = settle(now);
    if (s.status != FocusStatus.running) return s;
    return s._copy(status: FocusStatus.paused, pausedAt: now);
  }

  FocusSession resume(DateTime now) {
    if (status != FocusStatus.paused) return this;
    return FocusSession(
      id: id,
      spaceId: spaceId,
      spotId: spotId,
      plannedMinutes: plannedMinutes,
      startedAt: startedAt,
      pausedTotal: pausedTotal + now.difference(pausedAt!),
      status: FocusStatus.running,
    );
  }

  /// Ends early (or settles to completed if time was already up).
  FocusSession end(DateTime now) {
    final s = settle(now);
    if (!s.isActive) return s;
    final at = s.status == FocusStatus.paused ? s.pausedAt! : now;
    return s._copy(status: FocusStatus.ended, finishedAt: at);
  }

  FocusSession _copy({FocusStatus? status, DateTime? pausedAt, DateTime? finishedAt}) => FocusSession(
    id: id,
    spaceId: spaceId,
    spotId: spotId,
    plannedMinutes: plannedMinutes,
    startedAt: startedAt,
    pausedTotal: pausedTotal,
    pausedAt: pausedAt ?? this.pausedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    status: status ?? this.status,
  );

  static String? validateMinutes(int? m) {
    if (m == null) return 'Choose a duration.';
    if (m < minMinutes || m > maxMinutes) return 'Duration must be $minMinutes–$maxMinutes minutes.';
    return null;
  }

  factory FocusSession.start({required String spaceId, required String spotId, required int minutes, required DateTime now}) {
    final err = validateMinutes(minutes);
    if (err != null) throw ArgumentError(err);
    return FocusSession(
      id: 'focus-${now.microsecondsSinceEpoch}',
      spaceId: spaceId,
      spotId: spotId,
      plannedMinutes: minutes,
      startedAt: now,
    );
  }

  factory FocusSession.fromJson(Map<String, dynamic> j) => FocusSession(
    id: j['id'] as String,
    spaceId: j['spaceId'] as String,
    spotId: j['spotId'] as String,
    plannedMinutes: (j['plannedMinutes'] as num).toInt(),
    startedAt: DateTime.parse(j['startedAt'] as String),
    pausedTotal: Duration(milliseconds: (j['pausedTotalMs'] as num?)?.toInt() ?? 0),
    pausedAt: j['pausedAt'] == null ? null : DateTime.parse(j['pausedAt'] as String),
    finishedAt: j['finishedAt'] == null ? null : DateTime.parse(j['finishedAt'] as String),
    status: FocusStatus.values.byName(j['status'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceId': spaceId,
    'spotId': spotId,
    'plannedMinutes': plannedMinutes,
    'startedAt': startedAt.toIso8601String(),
    'pausedTotalMs': pausedTotal.inMilliseconds,
    'pausedAt': pausedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'status': status.name,
  };
}

/// A place a student can sit. Positions are normalised (0..1) within the
/// space's illustration; [verified] is false for conceptual layouts.
class StudySpot {
  final String id;
  final String label;
  final double x, y;
  const StudySpot(this.id, this.label, this.x, this.y);
}

class StudySpace {
  final String id;
  final String name;
  final String roomId; // validated room record the space belongs to
  final String floorId;
  final bool layoutVerified;
  final String layoutNote;
  final List<StudySpot> spots;
  const StudySpace({
    required this.id,
    required this.name,
    required this.roomId,
    required this.floorId,
    required this.layoutVerified,
    required this.layoutNote,
    required this.spots,
  });
}

/// The Library is a real region on the supplied Floor 7 plan; its interior
/// desk arrangement is NOT in any source, so the desks are conceptual.
final libraryStudySpace = StudySpace(
  id: 'library-f7',
  name: 'Library · Floor 7',
  roomId: 'LAB-LIBRARY',
  floorId: '7',
  layoutVerified: false,
  layoutNote:
      'Illustrative study hall: the Library location comes from the Floor 7 plan, '
      'but desk positions are not surveyed.',
  spots: [
    for (var r = 0; r < 3; r++)
      for (var c = 0; c < 4; c++)
        StudySpot('desk-${(r * 4 + c + 1).toString().padLeft(2, '0')}', 'Desk ${r * 4 + c + 1}', 0.17 + c * 0.22, 0.30 + r * 0.24),
  ],
);

/// Summary for completed-session history.
class FocusStats {
  final int sessions;
  final Duration total;
  const FocusStats(this.sessions, this.total);

  factory FocusStats.of(Iterable<FocusSession> history, DateTime now) {
    var total = Duration.zero;
    var n = 0;
    for (final s in history) {
      total += s.focusedAt(now);
      n++;
    }
    return FocusStats(n, total);
  }
}
