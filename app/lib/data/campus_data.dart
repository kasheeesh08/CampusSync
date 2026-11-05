import '../domain/availability.dart';
import '../domain/models.dart';

/// Where a [CampusData] snapshot came from; shown to users so stale or demo
/// data is never presented as live.
enum DataOrigin { server, cache, bundledDemo }

/// Immutable snapshot of all read-side campus data.
class CampusData {
  final String institutionName;
  final List<NamedEntity> departments;
  final List<NamedEntity> programs;
  final List<NamedEntity> academicYears;
  final List<AcademicGroup> groups;
  final List<Subject> subjects;
  final List<Faculty> faculty;
  final List<Room> rooms;
  final List<FloorLayout> floors;
  final List<TimetableVersion> versions;
  final List<ElectiveOffering> electives;
  final List<Announcement> announcements;
  final List<Exam> exams;
  final List<CalendarEvent> calendarEvents;
  final Map<String, String> calendarAudienceLabels;
  final List<Map<String, dynamic>> importJobs;
  final CampusSettings settings;
  final DataOrigin origin;
  final DateTime? syncedAt;

  CampusData({
    required this.institutionName,
    required this.departments,
    required this.programs,
    required this.academicYears,
    required this.groups,
    required this.subjects,
    required this.faculty,
    required this.rooms,
    required this.floors,
    required this.versions,
    required this.electives,
    required this.announcements,
    required this.exams,
    required this.calendarEvents,
    required this.calendarAudienceLabels,
    this.importJobs = const [],
    required this.settings,
    required this.origin,
    this.syncedAt,
  });

  late final Map<String, Room> roomsById = {for (final r in rooms) r.id: r};
  late final Map<String, AcademicGroup> groupsById = {for (final g in groups) g.id: g};
  late final Map<String, Faculty> facultyById = {for (final f in faculty) f.id: f};
  late final Map<String, Subject> subjectsByCode = {for (final s in subjects) s.code: s};
  late final Map<String, ElectiveOffering> electivesById = {for (final e in electives) e.id: e};

  late final AvailabilityEngine availability = AvailabilityEngine(rooms: rooms, groups: groups, versions: versions, settings: settings);

  /// Odd-semester Term End Exam window from the academic calendar, if present.
  CalendarEvent? get termEndExamWindow =>
      calendarEvents.where((e) => e.category == 'termEndExam' && e.audience == 'btech-mbatech-year2to6' && e.term == 'odd').firstOrNull;

  List<AcademicGroup> get divisionGroups => groups.where((g) => g.isDivision && g.active).toList();

  String subjectName(TimetableEntry e) => e.subjectName ?? subjectsByCode[e.subjectCode]?.name ?? e.subjectCode ?? e.kind.wire;

  String? facultyName(TimetableEntry e) => e.facultyName ?? facultyById[e.facultyId]?.name;

  String roomDisplay(String? roomId) => roomId == null ? '—' : (roomsById[roomId]?.name ?? roomId);

  CampusData copyWith({DataOrigin? origin, DateTime? syncedAt}) => CampusData(
    institutionName: institutionName,
    departments: departments,
    programs: programs,
    academicYears: academicYears,
    groups: groups,
    subjects: subjects,
    faculty: faculty,
    rooms: rooms,
    floors: floors,
    versions: versions,
    electives: electives,
    announcements: announcements,
    exams: exams,
    calendarEvents: calendarEvents,
    calendarAudienceLabels: calendarAudienceLabels,
    importJobs: importJobs,
    settings: settings,
    origin: origin ?? this.origin,
    syncedAt: syncedAt ?? this.syncedAt,
  );

  /// Builds a snapshot from the bundled seed files (keyed by file name without
  /// extension) or from the equivalent cached/serialized form.
  factory CampusData.fromSeed(Map<String, dynamic> seed, {DataOrigin origin = DataOrigin.bundledDemo, DateTime? syncedAt}) {
    List<Map<String, dynamic>> list(String file, String key) => [
      for (final m in ((seed[file] as Map?)?[key] as List? ?? const [])) Map<String, dynamic>.from(m as Map),
    ];
    final academic = list('academic', 'institutions');
    final campus = Map<String, dynamic>.from(seed['campus'] as Map? ?? const {});
    final audiences = Map<String, dynamic>.from((seed['calendar'] as Map?)?['audiences'] as Map? ?? const {});
    return CampusData(
      institutionName: academic.isEmpty ? 'MPSTME' : academic.first['name'] as String,
      departments: [
        for (final d in list('academic', 'departments'))
          NamedEntity(id: d['id'], name: d['name'], parentId: d['institutionId'], active: d['active'] != false),
      ],
      programs: [
        for (final p in list('academic', 'programs'))
          NamedEntity(id: p['id'], name: p['name'], parentId: p['departmentId'], active: p['active'] != false),
      ],
      academicYears: [
        for (final y in list('academic', 'academicYears')) NamedEntity(id: y['id'], name: y['label'], active: y['active'] != false),
      ],
      groups: list('academic', 'groups').map(AcademicGroup.fromJson).toList(),
      subjects: list('academic', 'subjects').map(Subject.fromJson).toList(),
      faculty: list('academic', 'faculty').map(Faculty.fromJson).toList(),
      rooms: list('campus', 'rooms').map(Room.fromJson).toList(),
      floors: list('campus', 'floors').map(FloorLayout.fromJson).toList()..sort((a, b) => a.order.compareTo(b.order)),
      versions: list('timetables', 'versions').map(TimetableVersion.fromJson).toList(),
      electives: list('electives', 'offerings').map(ElectiveOffering.fromJson).toList(),
      announcements: list('announcements', 'announcements').map(Announcement.fromJson).toList(),
      exams: list('exams', 'exams').map(Exam.fromJson).toList(),
      calendarEvents: list('calendar', 'events').map(CalendarEvent.fromJson).toList(),
      calendarAudienceLabels: {for (final e in audiences.entries) e.key: ((e.value as Map)['label'] ?? e.key).toString()},
      importJobs: list('imports', 'jobs'),
      settings: CampusSettings.fromJson(Map<String, dynamic>.from(campus['settings'] as Map? ?? const {})),
      origin: origin,
      syncedAt: syncedAt,
    );
  }

  /// Inverse of [CampusData.fromSeed]; used for the offline cache.
  Map<String, dynamic> toSeed() => {
    'academic': {
      'institutions': [
        {'id': 'institution', 'name': institutionName},
      ],
      'departments': [
        for (final d in departments) {'id': d.id, 'name': d.name, 'institutionId': d.parentId, 'active': d.active},
      ],
      'programs': [
        for (final p in programs) {'id': p.id, 'name': p.name, 'departmentId': p.parentId, 'active': p.active},
      ],
      'academicYears': [
        for (final y in academicYears) {'id': y.id, 'label': y.name, 'active': y.active},
      ],
      'groups': [for (final g in groups) g.toJson()],
      'subjects': [for (final s in subjects) s.toJson()],
      'faculty': [for (final f in faculty) f.toJson()],
    },
    'campus': {
      'settings': settings.toJson(),
      'rooms': [for (final r in rooms) r.toJson()],
      'floors': [for (final f in floors) f.toJson()],
    },
    'timetables': {
      'versions': [for (final v in versions) v.toJson()],
    },
    'electives': {
      'offerings': [
        for (final e in electives)
          {
            'id': e.id,
            'slot': e.slot,
            'name': e.name,
            'offeringDepartment': e.offeringDepartment,
            'roomIds': e.roomIds,
            'labRoomId': e.labRoomId,
            'faculty': e.faculty,
            'reviewFlags': e.reviewFlags,
          },
      ],
    },
    'announcements': {
      'announcements': [for (final a in announcements) a.toJson()],
    },
    'exams': {
      'exams': [for (final e in exams) e.toJson()],
    },
    'calendar': {
      'audiences': {
        for (final e in calendarAudienceLabels.entries) e.key: {'label': e.value},
      },
      'events': [for (final e in calendarEvents) e.toJson()],
    },
    'imports': {'jobs': importJobs},
  };
}
