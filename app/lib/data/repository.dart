import '../domain/models.dart';
import 'campus_data.dart';

/// Identity recorded on every administrative write.
class Actor {
  final String uid;
  final String email;
  const Actor(this.uid, this.email);
}

enum AdminRole {
  /// Full access, including timetables, rooms, groups, students and admins.
  admin,

  /// Announcements, exams and calendar events only.
  contentManager;

  static AdminRole? parse(String? v) => switch (v) {
    'admin' => admin,
    'contentManager' => contentManager,
    _ => null,
  };
}

class AdminAccount {
  final String uid;
  final String email;
  /// Null when the stored role is missing or unrecognised: such an account has
  /// no access (rules: isStaff, SECURITY_AUDIT L3) and is shown as invalid.
  final AdminRole? role;
  const AdminAccount(this.uid, this.email, this.role);
}

enum SapRelease { released, alreadyReleased }

/// Raised instead of touching a SAP ID claim that belongs to someone else (or no one).
RepositoryException sapNotHeld(StudentProfile s) => RepositoryException(
  '${s.email} does not hold SAP ID ${s.sapId}, so nothing was released. '
  'Reload the list: the ID may now belong to another student.',
);

class RepositoryException implements Exception {
  final String message;
  const RepositoryException(this.message);
  @override
  String toString() => message;
}

/// Read/write access to shared campus data. Security is enforced server-side
/// by Firestore rules; this interface only shapes requests.
abstract class CampusRepository {
  bool get isDemo;

  /// Students receive published content only; admins receive drafts too.
  /// [student] is the signed-in student (student app), used to ask only for
  /// the announcements and exams their audience may read.
  Future<CampusData> fetch({required bool asAdmin, StudentProfile? student});

  /// Active divisions students may request during registration (public).
  Future<List<AcademicGroup>> registrationGroups();

  Future<StudentProfile?> loadProfile(String uid);
  Future<void> registerProfile(StudentProfile profile);
  Future<void> updateOwnPreferences(String uid, Map<String, Object?> changes);

  Future<AdminRole?> adminRole(String uid);

  // ---- Administration -----------------------------------------------------
  Future<List<StudentProfile>> listStudents();
  Future<void> setStudentAccount(String uid, {required AccountStatus status, String? groupId, required Actor actor});

  /// Recovery for a wrongly claimed SAP ID: suspends [student], marks the
  /// profile `sapReleased` and frees the SAP ID, in one audited write, so the
  /// rightful student can register. Only the claim [student] actually holds is
  /// ever deleted (enforced by the security rules). Returns
  /// [SapRelease.alreadyReleased] without writing if this was done before;
  /// throws [RepositoryException] if the student does not hold the claim.
  /// A released account cannot be re-activated.
  Future<SapRelease> releaseSapId(StudentProfile student, Actor actor);

  Future<void> saveGroup(AcademicGroup group, Actor actor);
  Future<void> saveRoom(Room room, Actor actor);

  /// kind: departments | programs | academicYears
  Future<void> saveNamedEntity(String kind, NamedEntity entity, Actor actor);
  Future<void> saveFloor(FloorLayout floor, Actor actor);
  Future<void> saveSettings(CampusSettings settings, Actor actor);

  /// Saves a draft (never changes published content).
  Future<void> saveDraftVersion(TimetableVersion version, Actor actor);

  /// Publishes [version] and archives the previously published version(s) of
  /// the group whose effective range overlaps it, atomically.
  Future<void> publishVersion(TimetableVersion version, List<TimetableVersion> existing, Actor actor);
  Future<void> archiveVersion(TimetableVersion version, Actor actor);

  Future<void> saveAnnouncement(Announcement announcement, Actor actor);
  Future<void> saveExam(Exam exam, Actor actor);
  Future<void> deleteExam(String id, Actor actor);
  Future<void> saveCalendarEvent(CalendarEvent event, Actor actor);
  Future<void> deleteCalendarEvent(String id, Actor actor);

  Future<List<AdminAccount>> listAdmins();
  Future<void> setAdmin(String uid, String email, AdminRole? role, Actor actor);

  Future<List<AuditRecord>> listAudit({int limit = 100});
}

/// Computes the version documents to write when publishing.
List<TimetableVersion> planPublish(TimetableVersion candidate, List<TimetableVersion> existing, Actor actor, DateTime now) {
  final writes = <TimetableVersion>[];
  for (final v in existing) {
    if (v.groupId != candidate.groupId || v.id == candidate.id || v.status != VersionStatus.published) continue;
    final vEnd = v.effectiveTo ?? DateTime(9999);
    final cEnd = candidate.effectiveTo ?? DateTime(9999);
    final overlaps = !v.effectiveFrom.isAfter(cEnd) && !candidate.effectiveFrom.isAfter(vEnd);
    if (overlaps) writes.add(v.copyWith(status: VersionStatus.archived, updatedAt: now));
  }
  writes.add(candidate.copyWith(status: VersionStatus.published, publishedBy: actor.email, publishedAt: now, updatedAt: now));
  return writes;
}

/// Next version number for a group (versions are never renumbered).
int nextVersionNumber(String groupId, List<TimetableVersion> existing) =>
    existing.where((v) => v.groupId == groupId).fold(0, (m, v) => v.version > m ? v.version : m) + 1;
