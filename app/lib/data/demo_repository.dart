import '../domain/models.dart';
import 'campus_data.dart';
import 'repository.dart';

/// In-memory repository backed by the bundled seed data. Used when Firebase is
/// not configured. Writes live only for the current session and the UI labels
/// demo mode clearly; nothing here pretends to reach a server.
class DemoRepository implements CampusRepository {
  final Map<String, dynamic> _seed;
  late CampusData _data = CampusData.fromSeed(_seed);
  final _audit = <AuditRecord>[];
  final _students = <String, StudentProfile>{};
  final _sapClaims = <String, String>{}; // SAP ID -> uid, mirrors the Firestore sapIndex
  final _admins = <String, AdminAccount>{'demo-admin': const AdminAccount('demo-admin', 'demo-admin@local', AdminRole.admin)};

  DemoRepository(this._seed);

  @override
  bool get isDemo => true;

  @override
  Future<CampusData> fetch({required bool asAdmin, StudentProfile? student}) async {
    final d = _data;
    if (asAdmin) return d;
    return _rebuild(
      versions: d.versions.where((v) => v.status == VersionStatus.published).toList(),
      announcements: d.announcements.where((a) => a.status == PublishStatus.published).toList(),
      exams: d.exams.where((e) => e.status == PublishStatus.published).toList(),
      events: d.calendarEvents.where((e) => e.status == PublishStatus.published).toList(),
      base: d,
    );
  }

  CampusData _rebuild({
    CampusData? base,
    List<AcademicGroup>? groups,
    List<Room>? rooms,
    List<TimetableVersion>? versions,
    List<Announcement>? announcements,
    List<Exam>? exams,
    List<CalendarEvent>? events,
    CampusSettings? settings,
  }) {
    final d = base ?? _data;
    return CampusData(
      institutionName: d.institutionName,
      departments: d.departments,
      programs: d.programs,
      academicYears: d.academicYears,
      groups: groups ?? d.groups,
      subjects: d.subjects,
      faculty: d.faculty,
      rooms: rooms ?? d.rooms,
      floors: d.floors,
      versions: versions ?? d.versions,
      electives: d.electives,
      announcements: announcements ?? d.announcements,
      exams: exams ?? d.exams,
      calendarEvents: events ?? d.calendarEvents,
      calendarAudienceLabels: d.calendarAudienceLabels,
      importJobs: d.importJobs,
      settings: settings ?? d.settings,
      origin: DataOrigin.bundledDemo,
      syncedAt: DateTime.now(),
    );
  }

  List<T> _upsert<T>(List<T> list, T item, String Function(T) id) {
    final out = [...list];
    final i = out.indexWhere((x) => id(x) == id(item));
    i >= 0 ? out[i] = item : out.add(item);
    return out;
  }

  void _log(Actor a, String action, String path, [String? summary]) => _audit.insert(
    0,
    AuditRecord(
      id: 'demo-${_audit.length}',
      actorUid: a.uid,
      actorEmail: a.email,
      action: action,
      targetPath: path,
      summary: summary,
      at: DateTime.now(),
    ),
  );

  @override
  Future<List<AcademicGroup>> registrationGroups() async => _data.divisionGroups;

  @override
  Future<StudentProfile?> loadProfile(String uid) async => _students[uid];

  @override
  Future<void> registerProfile(StudentProfile profile) async {
    if (_sapClaims.containsKey(profile.sapId)) {
      throw const RepositoryException('An account with this SAP ID already exists.');
    }
    if (_students.containsKey(profile.uid)) throw const RepositoryException('This account already has a profile.');
    _sapClaims[profile.sapId] = profile.uid;
    _students[profile.uid] = profile;
  }

  @override
  Future<void> updateOwnPreferences(String uid, Map<String, Object?> changes) async {
    final s = _students[uid];
    if (s == null) return;
    _students[uid] = StudentProfile.fromJson({...s.toJson(), ...changes});
  }

  @override
  Future<AdminRole?> adminRole(String uid) async => _admins[uid]?.role;

  @override
  Future<List<StudentProfile>> listStudents() async => _students.values.toList();

  @override
  Future<void> setStudentAccount(String uid, {required AccountStatus status, String? groupId, required Actor actor}) async {
    final s = _students[uid];
    if (s == null) throw const RepositoryException('Student not found.');
    if (status == AccountStatus.active && _sapClaims[s.sapId] != uid) {
      throw const RepositoryException('This account no longer holds its SAP ID and cannot be approved.');
    }
    _students[uid] = s.copyWith(status: status, groupId: groupId);
    _log(actor, 'student.${status.name}', 'students/$uid', groupId);
  }

  @override
  Future<SapRelease> releaseSapId(StudentProfile student, Actor actor) async {
    final s = _students[student.uid];
    if (s == null) throw const RepositoryException('Student not found.');
    if (s.sapReleased) return SapRelease.alreadyReleased;
    if (_sapClaims[s.sapId] != s.uid) throw sapNotHeld(s);
    _students[s.uid] = s.copyWith(status: AccountStatus.suspended, sapReleased: true);
    _sapClaims.remove(s.sapId);
    _log(actor, 'student.releaseSapId', 'sapIndex/${s.sapId}', s.uid);
    return SapRelease.released;
  }

  @override
  Future<void> saveGroup(AcademicGroup group, Actor actor) async {
    _data = _rebuild(groups: _upsert(_data.groups, group, (g) => g.id));
    _log(actor, 'group.save', 'groups/${group.id}', group.label);
  }

  @override
  Future<void> saveRoom(Room room, Actor actor) async {
    _data = _rebuild(rooms: _upsert(_data.rooms, room, (r) => r.id));
    _log(actor, 'room.save', 'rooms/${room.id}', room.name);
  }

  @override
  Future<void> saveNamedEntity(String kind, NamedEntity e, Actor actor) async {
    final d = _data;
    List<NamedEntity> up(List<NamedEntity> l) => _upsert(l, e, (x) => x.id);
    _data = CampusData(
      institutionName: d.institutionName,
      departments: kind == 'departments' ? up(d.departments) : d.departments,
      programs: kind == 'programs' ? up(d.programs) : d.programs,
      academicYears: kind == 'academicYears' ? up(d.academicYears) : d.academicYears,
      groups: d.groups,
      subjects: d.subjects,
      faculty: d.faculty,
      rooms: d.rooms,
      floors: d.floors,
      versions: d.versions,
      electives: d.electives,
      announcements: d.announcements,
      exams: d.exams,
      calendarEvents: d.calendarEvents,
      calendarAudienceLabels: d.calendarAudienceLabels,
      settings: d.settings,
      origin: DataOrigin.bundledDemo,
      syncedAt: DateTime.now(),
    );
    _log(actor, '$kind.save', '$kind/${e.id}', e.name);
  }

  @override
  Future<void> saveFloor(FloorLayout floor, Actor actor) async {
    final d = _data;
    _data = CampusData(
      institutionName: d.institutionName,
      departments: d.departments,
      programs: d.programs,
      academicYears: d.academicYears,
      groups: d.groups,
      subjects: d.subjects,
      faculty: d.faculty,
      rooms: d.rooms,
      floors: _upsert(d.floors, floor, (f) => f.id),
      versions: d.versions,
      electives: d.electives,
      announcements: d.announcements,
      exams: d.exams,
      calendarEvents: d.calendarEvents,
      calendarAudienceLabels: d.calendarAudienceLabels,
      settings: d.settings,
      origin: DataOrigin.bundledDemo,
      syncedAt: DateTime.now(),
    );
    _log(actor, 'floor.save', 'floors/${floor.id}', floor.name);
  }

  @override
  Future<void> saveSettings(CampusSettings settings, Actor actor) async {
    _data = _rebuild(settings: settings);
    _log(actor, 'settings.save', 'settings/campus');
  }

  @override
  Future<void> saveDraftVersion(TimetableVersion version, Actor actor) async {
    final existing = _data.versions.where((v) => v.id == version.id).firstOrNull;
    if (existing != null && existing.status != VersionStatus.draft) {
      throw const RepositoryException('Only drafts can be edited. Create a new version instead.');
    }
    final draft = version.copyWith(status: VersionStatus.draft, updatedAt: DateTime.now(), createdBy: actor.email);
    _data = _rebuild(versions: _upsert(_data.versions, draft, (v) => v.id));
    _log(actor, 'timetable.saveDraft', 'timetableVersions/${version.id}', '${version.entries.length} entries');
  }

  @override
  Future<void> publishVersion(TimetableVersion version, List<TimetableVersion> existing, Actor actor) async {
    var versions = _data.versions;
    for (final w in planPublish(version, versions, actor, DateTime.now())) {
      versions = _upsert(versions, w, (v) => v.id);
    }
    _data = _rebuild(versions: versions);
    _log(actor, 'timetable.publish', 'timetableVersions/${version.id}', 'v${version.version}');
  }

  @override
  Future<void> archiveVersion(TimetableVersion version, Actor actor) async {
    _data = _rebuild(
      versions: _upsert(_data.versions, version.copyWith(status: VersionStatus.archived, updatedAt: DateTime.now()), (v) => v.id),
    );
    _log(actor, 'timetable.archive', 'timetableVersions/${version.id}');
  }

  @override
  Future<void> saveAnnouncement(Announcement a, Actor actor) async {
    _data = _rebuild(announcements: _upsert(_data.announcements, a, (x) => x.id));
    _log(actor, 'announcement.${a.status.name}', 'announcements/${a.id}', a.title);
  }

  @override
  Future<void> saveExam(Exam exam, Actor actor) async {
    _data = _rebuild(exams: _upsert(_data.exams, exam, (e) => e.id));
    _log(actor, 'exam.save', 'exams/${exam.id}', exam.subjectName);
  }

  @override
  Future<void> deleteExam(String id, Actor actor) async {
    _data = _rebuild(exams: _data.exams.where((e) => e.id != id).toList());
    _log(actor, 'exam.delete', 'exams/$id');
  }

  @override
  Future<void> saveCalendarEvent(CalendarEvent event, Actor actor) async {
    _data = _rebuild(events: _upsert(_data.calendarEvents, event, (e) => e.id));
    _log(actor, 'calendar.save', 'calendarEvents/${event.id}', event.title);
  }

  @override
  Future<void> deleteCalendarEvent(String id, Actor actor) async {
    _data = _rebuild(events: _data.calendarEvents.where((e) => e.id != id).toList());
    _log(actor, 'calendar.delete', 'calendarEvents/$id');
  }

  @override
  Future<List<AdminAccount>> listAdmins() async => _admins.values.toList();

  @override
  Future<void> setAdmin(String uid, String email, AdminRole? role, Actor actor) async {
    if (uid == actor.uid) throw const RepositoryException('You cannot change your own role.');
    role == null ? _admins.remove(uid) : _admins[uid] = AdminAccount(uid, email, role);
    _log(actor, role == null ? 'admin.revoke' : 'admin.grant', 'admins/$uid', role?.name);
  }

  @override
  Future<List<AuditRecord>> listAudit({int limit = 100}) async => _audit.take(limit).toList();
}
