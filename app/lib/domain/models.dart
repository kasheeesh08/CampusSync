/// Core CampusSync domain models. Plain Dart so they are shared by the student
/// app, the admin dashboard, the seed loader and unit tests.
library;

/// Minutes since midnight, e.g. "08:30" -> 510.
int parseHm(String hm) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hm.trim());
  if (match == null) throw FormatException('Invalid time "$hm" (expected HH:MM)');
  final h = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  if (h > 23 || m > 59) throw FormatException('Invalid time "$hm"');
  return h * 60 + m;
}

String formatHm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// "13:00" -> "1:00 PM".
String formatHm12(int minutes) {
  final h = minutes ~/ 60;
  final m = (minutes % 60).toString().padLeft(2, '0');
  final suffix = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m $suffix';
}

DateTime? parseDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  final d = DateTime.tryParse(v.toString());
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

String? formatDate(DateTime? d) =>
    d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

List<String> _strings(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

enum EntryKind {
  lecture,
  lab,
  tutorial,
  elective,
  breakPeriod,
  library;

  static EntryKind parse(String v) => switch (v) {
    'lecture' => lecture,
    'lab' => lab,
    'tutorial' => tutorial,
    'elective' => elective,
    'break' => breakPeriod,
    'library' => library,
    _ => throw FormatException('Unknown entry kind "$v"'),
  };

  String get wire => this == breakPeriod ? 'break' : name;

  /// Break and library periods are free periods for the student.
  bool get isFreePeriod => this == breakPeriod || this == library;
  bool get needsRoom => this == lecture || this == lab || this == tutorial;
}

class TimetableEntry {
  final String id;
  final int weekday; // DateTime.monday (1) .. DateTime.sunday (7)
  final int startMin;
  final int endMin;
  final EntryKind kind;
  final String? subjectCode;
  final String? subjectName;
  final String? facultyId;
  final String? facultyInitials;
  final String? facultyName;
  final String? roomId;
  final String? roomLabel;
  final String? batch;
  final String? sharedNote;
  final String? electiveOfferingId;
  final bool cancelled;
  final List<String> reviewFlags;

  const TimetableEntry({
    required this.id,
    required this.weekday,
    required this.startMin,
    required this.endMin,
    required this.kind,
    this.subjectCode,
    this.subjectName,
    this.facultyId,
    this.facultyInitials,
    this.facultyName,
    this.roomId,
    this.roomLabel,
    this.batch,
    this.sharedNote,
    this.electiveOfferingId,
    this.cancelled = false,
    this.reviewFlags = const [],
  });

  int get durationMin => endMin - startMin;

  bool overlaps(int start, int end) => startMin < end && start < endMin;

  factory TimetableEntry.fromJson(Map<String, dynamic> j) => TimetableEntry(
    id: j['id'] as String,
    weekday: (j['weekday'] as num).toInt(),
    startMin: parseHm(j['start'] as String),
    endMin: parseHm(j['end'] as String),
    kind: EntryKind.parse(j['kind'] as String),
    subjectCode: j['subjectCode'] as String?,
    subjectName: j['subjectName'] as String?,
    facultyId: j['facultyId'] as String?,
    facultyInitials: j['facultyInitials'] as String?,
    facultyName: j['facultyName'] as String?,
    roomId: j['roomId'] as String?,
    roomLabel: j['roomLabel'] as String?,
    batch: j['batch'] as String?,
    sharedNote: j['sharedNote'] as String?,
    electiveOfferingId: j['electiveOfferingId'] as String?,
    cancelled: j['cancelled'] == true,
    reviewFlags: _strings(j['reviewFlags']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'weekday': weekday,
    'start': formatHm(startMin),
    'end': formatHm(endMin),
    'kind': kind.wire,
    'subjectCode': subjectCode,
    'subjectName': subjectName,
    'facultyId': facultyId,
    'facultyInitials': facultyInitials,
    'facultyName': facultyName,
    'roomId': roomId,
    'roomLabel': roomLabel,
    'batch': batch,
    'sharedNote': sharedNote,
    'electiveOfferingId': electiveOfferingId,
    'cancelled': cancelled,
    'reviewFlags': reviewFlags,
  };

  TimetableEntry copyWith({String? id, String? roomId, bool? cancelled, int? startMin, int? endMin}) => TimetableEntry(
    id: id ?? this.id,
    weekday: weekday,
    startMin: startMin ?? this.startMin,
    endMin: endMin ?? this.endMin,
    kind: kind,
    subjectCode: subjectCode,
    subjectName: subjectName,
    facultyId: facultyId,
    facultyInitials: facultyInitials,
    facultyName: facultyName,
    roomId: roomId ?? this.roomId,
    roomLabel: roomLabel,
    batch: batch,
    sharedNote: sharedNote,
    electiveOfferingId: electiveOfferingId,
    cancelled: cancelled ?? this.cancelled,
    reviewFlags: reviewFlags,
  );
}

enum VersionStatus { draft, published, archived }

class TimetableVersion {
  final String id;
  final String groupId;
  final int version;
  final VersionStatus status;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? source;
  final String? createdBy;
  final String? publishedBy;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final List<TimetableEntry> entries;
  final List<String> reviewFlags;

  const TimetableVersion({
    required this.id,
    required this.groupId,
    required this.version,
    required this.status,
    required this.effectiveFrom,
    this.effectiveTo,
    this.source,
    this.createdBy,
    this.publishedBy,
    this.publishedAt,
    this.updatedAt,
    this.entries = const [],
    this.reviewFlags = const [],
  });

  bool coversDate(DateTime date) {
    final d = dateOnly(date);
    if (d.isBefore(effectiveFrom)) return false;
    final to = effectiveTo;
    return to == null || !d.isAfter(to);
  }

  factory TimetableVersion.fromJson(Map<String, dynamic> j) => TimetableVersion(
    id: j['id'] as String,
    groupId: j['groupId'] as String,
    version: (j['version'] as num?)?.toInt() ?? 1,
    status: VersionStatus.values.byName(j['status'] as String? ?? 'draft'),
    effectiveFrom: parseDate(j['effectiveFrom'])!,
    effectiveTo: parseDate(j['effectiveTo']),
    source: j['source'] as String?,
    createdBy: j['createdBy'] as String?,
    publishedBy: j['publishedBy'] as String?,
    publishedAt: DateTime.tryParse(j['publishedAt']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
    entries: [for (final e in (j['entries'] as List? ?? const [])) TimetableEntry.fromJson(Map<String, dynamic>.from(e as Map))],
    reviewFlags: _strings(j['reviewFlags']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'version': version,
    'status': status.name,
    'effectiveFrom': formatDate(effectiveFrom),
    'effectiveTo': formatDate(effectiveTo),
    'source': source,
    'createdBy': createdBy,
    'publishedBy': publishedBy,
    'publishedAt': publishedAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'entries': [for (final e in entries) e.toJson()],
    'reviewFlags': reviewFlags,
  };

  TimetableVersion copyWith({
    String? id,
    int? version,
    VersionStatus? status,
    DateTime? effectiveFrom,
    DateTime? effectiveTo,
    String? publishedBy,
    DateTime? publishedAt,
    DateTime? updatedAt,
    String? createdBy,
    List<TimetableEntry>? entries,
  }) => TimetableVersion(
    id: id ?? this.id,
    groupId: groupId,
    version: version ?? this.version,
    status: status ?? this.status,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    effectiveTo: effectiveTo ?? this.effectiveTo,
    source: source,
    createdBy: createdBy ?? this.createdBy,
    publishedBy: publishedBy ?? this.publishedBy,
    publishedAt: publishedAt ?? this.publishedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    entries: entries ?? this.entries,
    reviewFlags: reviewFlags,
  );
}

class AcademicGroup {
  final String id;
  final String type; // division | electivePool
  final String? programId;
  final String? departmentId;
  final String academicYearId;
  final int? yearOfStudy;
  final int semester;
  final String? division;
  final String label;
  final bool active;
  final List<String> batches;

  const AcademicGroup({
    required this.id,
    required this.type,
    this.programId,
    this.departmentId,
    required this.academicYearId,
    this.yearOfStudy,
    required this.semester,
    this.division,
    required this.label,
    this.active = true,
    this.batches = const [],
  });

  bool get isDivision => type == 'division';

  factory AcademicGroup.fromJson(Map<String, dynamic> j) => AcademicGroup(
    id: j['id'] as String,
    type: j['type'] as String? ?? 'division',
    programId: j['programId'] as String?,
    departmentId: j['departmentId'] as String?,
    academicYearId: j['academicYearId'] as String,
    yearOfStudy: (j['yearOfStudy'] as num?)?.toInt(),
    semester: (j['semester'] as num).toInt(),
    division: j['division'] as String?,
    label: j['label'] as String,
    active: j['active'] != false,
    batches: _strings(j['batches']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'programId': programId,
    'departmentId': departmentId,
    'academicYearId': academicYearId,
    'yearOfStudy': yearOfStudy,
    'semester': semester,
    'division': division,
    'label': label,
    'active': active,
    'batches': batches,
  };

  AcademicGroup copyWith({String? label, bool? active, List<String>? batches}) => AcademicGroup(
    id: id,
    type: type,
    programId: programId,
    departmentId: departmentId,
    academicYearId: academicYearId,
    yearOfStudy: yearOfStudy,
    semester: semester,
    division: division,
    label: label ?? this.label,
    active: active ?? this.active,
    batches: batches ?? this.batches,
  );
}

/// Simple id/name entity used for departments, programs and academic years.
class NamedEntity {
  final String id;
  final String name;
  final String? parentId;
  final bool active;
  const NamedEntity({required this.id, required this.name, this.parentId, this.active = true});
}

class Room {
  final String id;
  final String code;
  final String name;
  final String type; // classroom | lab | tutorial | facility
  final String floorId;
  final int? capacity;
  final bool active;
  final bool bookable;
  final List<String> aliases;
  final String? restrictionNote;

  const Room({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.floorId,
    this.capacity,
    this.active = true,
    this.bookable = true,
    this.aliases = const [],
    this.restrictionNote,
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: j['id'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
    type: j['type'] as String,
    floorId: j['floorId'] as String,
    capacity: (j['capacity'] as num?)?.toInt(),
    active: j['active'] != false,
    bookable: j['bookable'] != false,
    aliases: _strings(j['aliases']),
    restrictionNote: j['restrictionNote'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'type': type,
    'floorId': floorId,
    'capacity': capacity,
    'active': active,
    'bookable': bookable,
    'aliases': aliases,
    'restrictionNote': restrictionNote,
  };

  Room copyWith({String? name, String? type, int? capacity, bool? active, bool? bookable, String? restrictionNote}) => Room(
    id: id,
    code: code,
    name: name ?? this.name,
    type: type ?? this.type,
    floorId: floorId,
    capacity: capacity ?? this.capacity,
    active: active ?? this.active,
    bookable: bookable ?? this.bookable,
    aliases: aliases,
    restrictionNote: restrictionNote ?? this.restrictionNote,
  );

  bool matches(String query) {
    final q = query.toLowerCase().replaceAll(RegExp(r'[\s\-.]'), '');
    if (q.isEmpty) return true;
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-.]'), '');
    return norm(code).contains(q) || norm(name).contains(q) || aliases.any((a) => norm(a).contains(q));
  }
}

class FloorRegion {
  final String id;
  final String label;
  final String kind;
  final String? roomId;
  final double x, y, w, h;

  const FloorRegion({
    required this.id,
    required this.label,
    required this.kind,
    this.roomId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory FloorRegion.fromJson(Map<String, dynamic> j) => FloorRegion(
    id: j['id'] as String,
    label: j['label'] as String,
    kind: j['kind'] as String,
    roomId: j['roomId'] as String?,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    w: (j['w'] as num).toDouble(),
    h: (j['h'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'kind': kind, 'roomId': roomId, 'x': x, 'y': y, 'w': w, 'h': h};
}

class FloorLayout {
  final String id;
  final String name;
  final int order;
  final String? note;
  final double aspectRatio;
  final bool missingLayout;
  final List<FloorRegion> regions;

  const FloorLayout({
    required this.id,
    required this.name,
    required this.order,
    this.note,
    required this.aspectRatio,
    this.missingLayout = false,
    this.regions = const [],
  });

  String get shortLabel => switch (id) {
    'LG' => 'LG',
    'G' => 'G',
    _ => id,
  };

  factory FloorLayout.fromJson(Map<String, dynamic> j) => FloorLayout(
    id: j['id'] as String,
    name: j['name'] as String,
    order: (j['order'] as num).toInt(),
    note: j['note'] as String?,
    aspectRatio: (j['aspectRatio'] as num).toDouble(),
    missingLayout: j['missingLayout'] == true,
    regions: [for (final r in (j['regions'] as List? ?? const [])) FloorRegion.fromJson(Map<String, dynamic>.from(r as Map))],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'order': order,
    'note': note,
    'aspectRatio': aspectRatio,
    'missingLayout': missingLayout,
    'regions': [for (final r in regions) r.toJson()],
  };
}

class Subject {
  final String code;
  final String name;
  const Subject({required this.code, required this.name});
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(code: j['code'] as String, name: j['name'] as String);
  Map<String, dynamic> toJson() => {'code': code, 'name': name};
}

class Faculty {
  final String id;
  final String name;
  final List<String> initials;
  const Faculty({required this.id, required this.name, this.initials = const []});
  factory Faculty.fromJson(Map<String, dynamic> j) =>
      Faculty(id: j['id'] as String, name: j['name'] as String, initials: _strings(j['initials']));
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'initials': initials};
}

class ElectiveOffering {
  final String id;
  final String slot; // OE-1 | OE-2
  final String name;
  final String? offeringDepartment;
  final List<String> roomIds;
  final String? labRoomId;
  final String? faculty;
  final List<String> reviewFlags;

  const ElectiveOffering({
    required this.id,
    required this.slot,
    required this.name,
    this.offeringDepartment,
    this.roomIds = const [],
    this.labRoomId,
    this.faculty,
    this.reviewFlags = const [],
  });

  factory ElectiveOffering.fromJson(Map<String, dynamic> j) => ElectiveOffering(
    id: j['id'] as String,
    slot: j['slot'] as String,
    name: j['name'] as String,
    offeringDepartment: j['offeringDepartment'] as String?,
    roomIds: _strings(j['roomIds']),
    labRoomId: j['labRoomId'] as String?,
    faculty: j['faculty'] as String?,
    reviewFlags: _strings(j['reviewFlags']),
  );
}

enum PublishStatus {
  draft,
  published,
  archived;

  /// Missing or unknown values are treated as draft (hidden from students),
  /// matching Firestore, where status-filtered queries never return them.
  static PublishStatus parse(Object? v) => values.asNameMap()[v] ?? draft;
}

class AnnouncementAudience {
  final String scope; // all | department | groups
  final List<String> ids;
  const AnnouncementAudience({this.scope = 'all', this.ids = const []});

  bool includes({String? groupId, String? departmentId}) => switch (scope) {
    'all' => true,
    'department' => departmentId != null && ids.contains(departmentId),
    'groups' => groupId != null && ids.contains(groupId),
    _ => false,
  };

  factory AnnouncementAudience.fromJson(Map<String, dynamic>? j) =>
      AnnouncementAudience(scope: j?['scope'] as String? ?? 'all', ids: _strings(j?['ids']));
  Map<String, dynamic> toJson() => {'scope': scope, 'ids': ids};

  /// Denormalised targeting stored as `audienceKeys`; the security rules let a
  /// student read a record only if one of these matches their audience.
  List<String> get keys => switch (scope) {
    'all' => const ['all'],
    'department' => [for (final id in ids) 'dept:$id'],
    _ => [for (final id in ids) 'group:$id'],
  };
}

class Announcement {
  final String id;
  final String title;
  final PublishStatus status;
  final String category;
  final String? summary;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? registrationUrl;
  final String? imageUrl;
  final AnnouncementAudience audience;
  final String? source;
  final DateTime? updatedAt;
  final List<String> reviewFlags;

  const Announcement({
    required this.id,
    required this.title,
    this.status = PublishStatus.draft,
    this.category = 'general',
    this.summary,
    this.description,
    this.startDate,
    this.endDate,
    this.registrationUrl,
    this.imageUrl,
    this.audience = const AnnouncementAudience(),
    this.source,
    this.updatedAt,
    this.reviewFlags = const [],
  });

  /// upcoming | ongoing | expired | undated, relative to [today].
  String timing(DateTime today) {
    final d = dateOnly(today);
    if (startDate == null && endDate == null) return 'undated';
    if (endDate != null && d.isAfter(endDate!)) return 'expired';
    if (startDate != null && d.isBefore(startDate!)) return 'upcoming';
    return 'ongoing';
  }

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
    id: j['id'] as String,
    title: j['title'] as String,
    status: PublishStatus.parse(j['status']),
    category: j['category'] as String? ?? 'general',
    summary: j['summary'] as String?,
    description: j['description'] as String?,
    startDate: parseDate(j['startDate']),
    endDate: parseDate(j['endDate']),
    registrationUrl: j['registrationUrl'] as String?,
    imageUrl: j['imageUrl'] as String?,
    audience: AnnouncementAudience.fromJson((j['audience'] as Map?)?.cast<String, dynamic>()),
    source: j['source'] as String?,
    updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
    reviewFlags: _strings(j['reviewFlags']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.name,
    'category': category,
    'summary': summary,
    'description': description,
    'startDate': formatDate(startDate),
    'endDate': formatDate(endDate),
    'registrationUrl': registrationUrl,
    'imageUrl': imageUrl,
    'audience': audience.toJson(),
    'audienceKeys': audience.keys,
    'source': source,
    'updatedAt': updatedAt?.toIso8601String(),
    'reviewFlags': reviewFlags,
  };
}

class Exam {
  final String id;
  final List<String> groupIds; // academic groups that sit this exam
  final List<String> electiveOfferingIds; // or: students who chose one of these electives
  final String subjectCode;
  final String subjectName;
  final String? officialCode; // course code printed in the official timetable
  final String? stream; // column/stream heading in the source
  final DateTime date;
  final String? startTime;
  final String? endTime;
  final String? timeSource; // "cell" (printed for the subject) | "page default"
  final String? session;
  final String? room;
  final PublishStatus status;
  final String? source;
  final List<String> reviewFlags;

  const Exam({
    required this.id,
    required this.groupIds,
    this.electiveOfferingIds = const [],
    required this.subjectCode,
    required this.subjectName,
    this.officialCode,
    this.stream,
    required this.date,
    this.startTime,
    this.endTime,
    this.timeSource,
    this.session,
    this.room,
    this.status = PublishStatus.published,
    this.source,
    this.reviewFlags = const [],
  });

  /// Whether a student in [groupId] with the given elective choices sits this exam.
  bool appliesTo({String? groupId, Iterable<String?> electiveIds = const []}) =>
      (groupId != null && groupIds.contains(groupId)) || electiveIds.any((e) => e != null && electiveOfferingIds.contains(e));

  /// Denormalised targeting stored as `audienceKeys` (see [AnnouncementAudience.keys]).
  List<String> get audienceKeys => [for (final g in groupIds) 'group:$g', for (final o in electiveOfferingIds) 'oe:$o'];

  int? get startMin => startTime == null ? null : parseHm(startTime!);
  int? get endMin => endTime == null ? null : parseHm(endTime!);

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
    id: j['id'] as String,
    groupIds: _strings(j['groupIds']),
    electiveOfferingIds: _strings(j['electiveOfferingIds']),
    subjectCode: j['subjectCode'] as String,
    subjectName: j['subjectName'] as String,
    officialCode: j['officialCode'] as String?,
    stream: j['stream'] as String?,
    date: parseDate(j['date'])!,
    startTime: j['startTime'] as String?,
    endTime: j['endTime'] as String?,
    timeSource: j['timeSource'] as String?,
    session: j['session'] as String?,
    room: j['room'] as String?,
    status: PublishStatus.parse(j['status']),
    source: j['source'] as String?,
    reviewFlags: _strings(j['reviewFlags']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupIds': groupIds,
    'electiveOfferingIds': electiveOfferingIds,
    'audienceKeys': audienceKeys,
    'subjectCode': subjectCode,
    'subjectName': subjectName,
    'officialCode': officialCode,
    'stream': stream,
    'date': formatDate(date),
    'startTime': startTime,
    'endTime': endTime,
    'timeSource': timeSource,
    'session': session,
    'room': room,
    'status': status.name,
    'source': source,
    'reviewFlags': reviewFlags,
  };

  Exam copyWith({PublishStatus? status, List<String>? groupIds}) => Exam(
    id: id,
    groupIds: groupIds ?? this.groupIds,
    electiveOfferingIds: electiveOfferingIds,
    subjectCode: subjectCode,
    subjectName: subjectName,
    officialCode: officialCode,
    stream: stream,
    date: date,
    startTime: startTime,
    endTime: endTime,
    timeSource: timeSource,
    session: session,
    room: room,
    status: status ?? this.status,
    source: source,
    reviewFlags: reviewFlags,
  );
}

class CalendarEvent {
  final String id;
  final String title;
  final String category;
  final DateTime start;
  final DateTime end;
  final String term;
  final String audience;
  final String? source;
  final PublishStatus status;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.start,
    required this.end,
    required this.term,
    required this.audience,
    this.source,
    this.status = PublishStatus.published,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
    id: j['id'] as String,
    title: j['title'] as String,
    category: j['category'] as String,
    start: parseDate(j['start'])!,
    end: parseDate(j['end'])!,
    term: j['term'] as String,
    audience: j['audience'] as String,
    source: j['source'] as String?,
    status: PublishStatus.parse(j['status']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'start': formatDate(start),
    'end': formatDate(end),
    'term': term,
    'audience': audience,
    'source': source,
    'status': status.name,
  };
}

class CampusSettings {
  final String timezone;
  final int dayStartMin;
  final int dayEndMin;
  final bool coverageDeclaredComplete;
  final String? coverageNote;

  const CampusSettings({
    this.timezone = 'Asia/Kolkata',
    this.dayStartMin = 8 * 60,
    this.dayEndMin = 18 * 60,
    this.coverageDeclaredComplete = false,
    this.coverageNote,
  });

  factory CampusSettings.fromJson(Map<String, dynamic> j) => CampusSettings(
    timezone: j['timezone'] as String? ?? 'Asia/Kolkata',
    dayStartMin: parseHm(j['dayStart'] as String? ?? '08:00'),
    dayEndMin: parseHm(j['dayEnd'] as String? ?? '18:00'),
    coverageDeclaredComplete: j['coverageDeclaredComplete'] == true,
    coverageNote: j['coverageNote'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'timezone': timezone,
    'dayStart': formatHm(dayStartMin),
    'dayEnd': formatHm(dayEndMin),
    'coverageDeclaredComplete': coverageDeclaredComplete,
    'coverageNote': coverageNote,
  };
}

enum AccountStatus { pending, active, suspended }

/// The audience keys a student may read (mirrors `studentAudience()` in
/// firestore.rules; absent values are left out, so the query asks for a subset).
List<String> studentAudienceKeys(StudentProfile p, String? departmentId) => [
  'all',
  if (p.groupId != null) 'group:${p.groupId}',
  if (departmentId != null) 'dept:$departmentId',
  if (p.oe1OfferingId != null) 'oe:${p.oe1OfferingId}',
  if (p.oe2OfferingId != null && p.oe2OfferingId != p.oe1OfferingId) 'oe:${p.oe2OfferingId}',
];

class StudentProfile {
  final String uid;
  final String email;
  final String displayName;
  final String sapId;
  final String rollNumber;
  final String? requestedGroupId;
  final String? groupId; // assigned by an administrator on approval
  final String? batch;
  final String? oe1OfferingId;
  final String? oe2OfferingId;
  final String avatar;
  final AccountStatus status;

  /// Set by an administrator when this account's SAP ID claim was released
  /// (recovery for a wrongly claimed ID). Such an account stays suspended.
  final bool sapReleased;

  const StudentProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.sapId,
    required this.rollNumber,
    this.requestedGroupId,
    this.groupId,
    this.batch,
    this.oe1OfferingId,
    this.oe2OfferingId,
    this.avatar = 'fox',
    this.status = AccountStatus.pending,
    this.sapReleased = false,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> j) => StudentProfile(
    uid: j['uid'] as String,
    email: j['email'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
    sapId: j['sapId'] as String? ?? '',
    rollNumber: j['rollNumber'] as String? ?? '',
    requestedGroupId: j['requestedGroupId'] as String?,
    groupId: j['groupId'] as String?,
    batch: j['batch'] as String?,
    oe1OfferingId: j['oe1OfferingId'] as String?,
    oe2OfferingId: j['oe2OfferingId'] as String?,
    avatar: j['avatar'] as String? ?? 'fox',
    status: AccountStatus.values.byName(j['status'] as String? ?? 'pending'),
    sapReleased: j['sapReleased'] == true,
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'sapId': sapId,
    'rollNumber': rollNumber,
    'requestedGroupId': requestedGroupId,
    'groupId': groupId,
    'batch': batch,
    'oe1OfferingId': oe1OfferingId,
    'oe2OfferingId': oe2OfferingId,
    'avatar': avatar,
    'status': status.name,
    // Only ever written by an administrator; absent on registration.
    if (sapReleased) 'sapReleased': true,
  };

  StudentProfile copyWith({
    String? displayName,
    String? groupId,
    String? batch,
    String? oe1OfferingId,
    String? oe2OfferingId,
    String? avatar,
    AccountStatus? status,
    bool? sapReleased,
  }) => StudentProfile(
    uid: uid,
    email: email,
    displayName: displayName ?? this.displayName,
    sapId: sapId,
    rollNumber: rollNumber,
    requestedGroupId: requestedGroupId,
    groupId: groupId ?? this.groupId,
    batch: batch ?? this.batch,
    oe1OfferingId: oe1OfferingId ?? this.oe1OfferingId,
    oe2OfferingId: oe2OfferingId ?? this.oe2OfferingId,
    avatar: avatar ?? this.avatar,
    status: status ?? this.status,
    sapReleased: sapReleased ?? this.sapReleased,
  );
}

class AuditRecord {
  final String id;
  final String actorUid;
  final String actorEmail;
  final String action;
  final String targetPath;
  final String? summary;
  final DateTime at;

  const AuditRecord({
    required this.id,
    required this.actorUid,
    required this.actorEmail,
    required this.action,
    required this.targetPath,
    this.summary,
    required this.at,
  });

  factory AuditRecord.fromJson(Map<String, dynamic> j) => AuditRecord(
    id: j['id'] as String,
    actorUid: j['actorUid'] as String? ?? '',
    actorEmail: j['actorEmail'] as String? ?? '',
    action: j['action'] as String? ?? '',
    targetPath: j['targetPath'] as String? ?? '',
    summary: j['summary'] as String?,
    at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'actorUid': actorUid,
    'actorEmail': actorEmail,
    'action': action,
    'targetPath': targetPath,
    'summary': summary,
    'at': at.toIso8601String(),
  };
}
