import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';
import 'campus_data.dart';
import 'registration_errors.dart';
import 'repository.dart';

/// Firestore-backed repository. Collection layout is documented in
/// docs/ARCHITECTURE.md and enforced by firebase/firestore.rules.
class FirestoreRepository implements CampusRepository {
  final FirebaseFirestore _db;
  FirestoreRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  @override
  bool get isDemo => false;

  CollectionReference<Map<String, dynamic>> _c(String name) => _db.collection(name);

  /// Set while a fetch runs; true if any query was answered from the local
  /// Firestore cache (offline), so the UI never labels cached data as live.
  bool _servedFromCache = false;

  Future<List<Map<String, dynamic>>> _all(Query<Map<String, dynamic>> q) async {
    final snap = await q.get();
    if (snap.metadata.isFromCache) _servedFromCache = true;
    return snap.docs.map((d) => {...d.data(), 'id': d.data()['id'] ?? d.id}).toList();
  }

  @override
  Future<CampusData> fetch({required bool asAdmin, StudentProfile? student}) async {
    Query<Map<String, dynamic>> versionsQ = _c('timetableVersions');
    Query<Map<String, dynamic>> annQ = _c('announcements');
    Query<Map<String, dynamic>> examQ = _c('exams');
    Query<Map<String, dynamic>> calQ = _c('calendarEvents');
    if (!asAdmin) {
      // Rules only allow students to read published records, so queries must say so.
      versionsQ = versionsQ.where('status', isEqualTo: 'published');
      annQ = annQ.where('status', isEqualTo: 'published');
      examQ = examQ.where('status', isEqualTo: 'published');
      calQ = calQ.where('status', isEqualTo: 'published');
      // Announcements and exams are readable only for the student's own
      // audience (rules: studentAudience), so the queries must ask for exactly that.
      final groupId = student?.groupId;
      if (student != null && groupId != null) {
        final group = await _c('groups').doc(groupId).get();
        final keys = studentAudienceKeys(student, group.data()?['departmentId'] as String?);
        annQ = annQ.where('audienceKeys', arrayContainsAny: keys);
        examQ = examQ.where('audienceKeys', arrayContainsAny: keys);
      }
    }
    _servedFromCache = false;
    final results = await Future.wait([
      _c('settings').doc('campus').get().then((d) {
        if (d.metadata.isFromCache) _servedFromCache = true;
        return d.data() ?? <String, dynamic>{};
      }),
      _all(_c('departments')),
      _all(_c('programs')),
      _all(_c('academicYears')),
      _all(_c('groups')),
      _all(_c('subjects')),
      _all(_c('faculty')),
      _all(_c('rooms')),
      _all(_c('floors')),
      _all(versionsQ),
      _all(_c('electives')),
      _all(annQ),
      _all(examQ),
      _all(calQ),
      asAdmin ? _all(_c('importJobs')) : Future.value(<Map<String, dynamic>>[]),
    ]);
    final settings = results[0] as Map<String, dynamic>;
    List<Map<String, dynamic>> at(int i) => results[i] as List<Map<String, dynamic>>;
    return CampusData.fromSeed(
      {
        'academic': {
          'institutions': [
            {'id': 'institution', 'name': settings['institutionName'] ?? 'MPSTME'},
          ],
          'departments': at(1),
          'programs': at(2),
          'academicYears': at(3),
          'groups': at(4),
          'subjects': at(5),
          'faculty': at(6),
        },
        'campus': {'settings': settings, 'rooms': at(7), 'floors': at(8)},
        'timetables': {'versions': at(9)},
        'electives': {'offerings': at(10)},
        'announcements': {'announcements': at(11)},
        'exams': {'exams': at(12)},
        'calendar': {
          'audiences': {
            for (final e in Map<String, dynamic>.from(settings['calendarAudienceLabels'] as Map? ?? const {}).entries)
              e.key: {'label': e.value},
          },
          'events': at(13),
        },
        'imports': {'jobs': at(14)},
      },
      origin: _servedFromCache ? DataOrigin.cache : DataOrigin.server,
      syncedAt: _servedFromCache ? null : DateTime.now(),
    );
  }

  @override
  Future<List<AcademicGroup>> registrationGroups() async {
    final snap = await _c('groups').where('type', isEqualTo: 'division').where('active', isEqualTo: true).get();
    return checkedRegistrationGroups(
      [for (final d in snap.docs) AcademicGroup.fromJson({...d.data(), 'id': d.data()['id'] ?? d.id})],
      fromCache: snap.metadata.isFromCache,
    );
  }

  @override
  Future<StudentProfile?> loadProfile(String uid) async {
    final d = await _c('students').doc(uid).get();
    return d.exists ? StudentProfile.fromJson({...d.data()!, 'uid': uid}) : null;
  }

  /// Creates the profile and claims the SAP ID atomically. Callers must use a
  /// verified, freshly refreshed sign-in (AppState.register does): only then
  /// do the rules let the claim be read, so the check below can tell a
  /// duplicate apart from other failures. Throws [RegistrationException].
  @override
  Future<void> registerProfile(StudentProfile p) async {
    final sapRef = _c('sapIndex').doc(p.sapId);
    // 1. Server-side claim check (never the local cache).
    if (await _claimHeldByOther(sapRef, p.uid, duringWrite: false)) {
      throw RegistrationException(RegistrationFailure.duplicateSapId);
    }
    // 2. Atomic claim + profile. The rules re-check the claim, so a race with
    //    another registration still cannot give one SAP ID two owners.
    //    Returns instead of throwing inside the transaction: on web, such
    //    exceptions arrive wrapped and lose their type.
    try {
      final claimed = await _db.runTransaction<bool>((tx) async {
        final existing = await tx.get(sapRef);
        if (existing.exists && existing.data()?['uid'] != p.uid) return false;
        tx.set(sapRef, {'uid': p.uid});
        tx.set(_c('students').doc(p.uid), {...p.toJson(), 'status': 'pending', 'groupId': null, 'createdAt': FieldValue.serverTimestamp()});
        return true;
      });
      if (!claimed) throw RegistrationException(RegistrationFailure.duplicateSapId);
    } on RegistrationException {
      rethrow;
    } catch (e) {
      // A denied write is either a lost race (someone claimed the SAP ID after
      // step 1) or details the rules rejected; re-check to tell them apart.
      if (firestoreErrorCode(e) == 'permission-denied' && await _claimHeldByOther(sapRef, p.uid, duringWrite: true)) {
        throw RegistrationException(RegistrationFailure.duplicateSapId);
      }
      throw classifyRegistrationError(e, duringWrite: true);
    }
  }

  /// True if another account holds [sapRef]. A verified user may read a claim
  /// only when it is free or their own, so "permission-denied" means taken.
  Future<bool> _claimHeldByOther(DocumentReference<Map<String, dynamic>> sapRef, String uid, {required bool duringWrite}) async {
    try {
      final claim = await sapRef.get(const GetOptions(source: Source.server));
      return claim.exists && claim.data()?['uid'] != uid;
    } catch (e) {
      final code = firestoreErrorCode(e);
      if (code == 'permission-denied') return true;
      throw classifyRegistrationError(e, duringWrite: duringWrite);
    }
  }

  static const selfEditable = {'displayName', 'avatar', 'batch', 'oe1OfferingId', 'oe2OfferingId'};

  @override
  Future<void> updateOwnPreferences(String uid, Map<String, Object?> changes) async {
    final filtered = {
      for (final e in changes.entries)
        if (selfEditable.contains(e.key)) e.key: e.value,
    };
    await _c('students').doc(uid).update(filtered);
  }

  @override
  Future<AdminRole?> adminRole(String uid) async {
    try {
      final d = await _c('admins').doc(uid).get();
      return d.exists ? AdminRole.parse(d.data()?['role'] as String?) : null;
    } on FirebaseException {
      return null; // non-admins may not read the collection
    }
  }

  Map<String, dynamic> _auditEntry(Actor a, String action, String path, [String? summary]) => {
    'actorUid': a.uid,
    'actorEmail': a.email,
    'action': action,
    'targetPath': path,
    'summary': summary,
    'at': DateTime.now().toUtc().toIso8601String(),
    'serverAt': FieldValue.serverTimestamp(),
  };

  /// A batch that already contains a new audit record, plus that record's id.
  /// Audited writes carry the id in `auditId`; the rules require the record to
  /// be created in the same commit by the same user (SECURITY_AUDIT M4).
  (WriteBatch, String) _batchWithAudit(Actor a, String action, String path, [String? summary]) {
    final audit = _c('auditLogs').doc();
    return (_db.batch()..set(audit, _auditEntry(a, action, path, summary)), audit.id);
  }

  Map<String, dynamic> _stamp(Map<String, dynamic> data, Actor a, String auditId) => {
    ...data,
    'updatedBy': a.uid,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'auditId': auditId,
  };

  Future<void> _save(String col, String id, Map<String, dynamic> data, Actor a, String action, [String? summary]) {
    final (batch, auditId) = _batchWithAudit(a, action, '$col/$id', summary);
    batch.set(_c(col).doc(id), _stamp(data, a, auditId));
    return batch.commit();
  }

  @override
  Future<List<StudentProfile>> listStudents() async =>
      (await _c('students').get()).docs.map((d) => StudentProfile.fromJson({...d.data(), 'uid': d.id})).toList();

  @override
  Future<void> setStudentAccount(String uid, {required AccountStatus status, String? groupId, required Actor actor}) {
    final (batch, auditId) = _batchWithAudit(actor, 'student.${status.name}', 'students/$uid', groupId);
    batch.update(_c('students').doc(uid), {'status': status.name, 'groupId': groupId, 'updatedBy': actor.uid, 'auditId': auditId});
    return batch.commit();
  }

  @override
  Future<SapRelease> releaseSapId(StudentProfile student, Actor actor) async {
    final studentRef = _c('students').doc(student.uid);
    var current = student;
    // Returns an outcome instead of throwing: on web, exceptions thrown inside
    // a transaction arrive wrapped and lose their message.
    final outcome = await _db.runTransaction<String>((tx) async {
      // Re-read both documents; the admin's list may be stale.
      final snap = await tx.get(studentRef);
      if (!snap.exists) return 'missing';
      current = StudentProfile.fromJson({...snap.data()!, 'uid': student.uid});
      if (current.sapReleased) return 'already';
      final claimRef = _c('sapIndex').doc(current.sapId);
      final claim = await tx.get(claimRef);
      if (!claim.exists || claim.data()?['uid'] != current.uid) return 'notHeld';
      // One write: the rules delete a claim only together with marking its
      // own holder suspended and released.
      final audit = _c('auditLogs').doc();
      tx.update(studentRef, {'status': AccountStatus.suspended.name, 'sapReleased': true, 'updatedBy': actor.uid, 'auditId': audit.id});
      tx.delete(claimRef);
      tx.set(audit, _auditEntry(actor, 'student.releaseSapId', 'sapIndex/${current.sapId}', current.uid));
      return 'released';
    });
    return switch (outcome) {
      'released' => SapRelease.released,
      'already' => SapRelease.alreadyReleased,
      'missing' => throw const RepositoryException('Student not found.'),
      _ => throw sapNotHeld(current),
    };
  }

  @override
  Future<void> saveGroup(AcademicGroup g, Actor a) => _save('groups', g.id, g.toJson(), a, 'group.save', g.label);

  @override
  Future<void> saveRoom(Room r, Actor a) => _save('rooms', r.id, r.toJson(), a, 'room.save', r.name);

  @override
  Future<void> saveNamedEntity(String kind, NamedEntity e, Actor a) {
    final parentKey = switch (kind) {
      'departments' => 'institutionId',
      'programs' => 'departmentId',
      _ => 'parentId',
    };
    final nameKey = kind == 'academicYears' ? 'label' : 'name';
    return _save(kind, e.id, {'id': e.id, nameKey: e.name, parentKey: e.parentId, 'active': e.active}, a, '$kind.save', e.name);
  }

  @override
  Future<void> saveFloor(FloorLayout f, Actor a) => _save('floors', f.id, f.toJson(), a, 'floor.save', f.name);

  @override
  Future<void> saveSettings(CampusSettings s, Actor a) {
    final (batch, auditId) = _batchWithAudit(a, 'settings.save', 'settings/campus');
    batch.set(_c('settings').doc('campus'), _stamp(s.toJson(), a, auditId), SetOptions(merge: true));
    return batch.commit();
  }

  @override
  Future<void> saveDraftVersion(TimetableVersion v, Actor a) async {
    final ref = _c('timetableVersions').doc(v.id);
    final existing = await ref.get();
    if (existing.exists && existing.data()?['status'] != 'draft') {
      throw const RepositoryException('Only drafts can be edited. Create a new version instead.');
    }
    await _save(
      'timetableVersions',
      v.id,
      v.copyWith(status: VersionStatus.draft, createdBy: a.email).toJson(),
      a,
      'timetable.saveDraft',
      '${v.entries.length} entries',
    );
  }

  @override
  Future<void> publishVersion(TimetableVersion v, List<TimetableVersion> existing, Actor a) {
    final (batch, auditId) = _batchWithAudit(a, 'timetable.publish', 'timetableVersions/${v.id}', 'v${v.version}');
    for (final w in planPublish(v, existing, a, DateTime.now())) {
      final ref = _c('timetableVersions').doc(w.id);
      final before = existing.where((e) => e.id == w.id).firstOrNull;
      if (before == null || before.status == VersionStatus.draft) {
        batch.set(ref, _stamp(w.toJson(), a, auditId));
      } else {
        // Published/archived versions are frozen (rules, SECURITY_AUDIT L1):
        // change only the status fields, never the content.
        batch.update(ref, {
          'status': w.status.name,
          if (w.status == VersionStatus.published) ...{'publishedBy': w.publishedBy, 'publishedAt': w.publishedAt?.toIso8601String()},
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'updatedBy': a.uid,
          'auditId': auditId,
        });
      }
    }
    return batch.commit();
  }

  @override
  Future<void> archiveVersion(TimetableVersion v, Actor a) {
    final (batch, auditId) = _batchWithAudit(a, 'timetable.archive', 'timetableVersions/${v.id}');
    batch.update(_c('timetableVersions').doc(v.id), {'status': 'archived', 'updatedBy': a.uid, 'auditId': auditId});
    return batch.commit();
  }

  @override
  Future<void> saveAnnouncement(Announcement x, Actor a) =>
      _save('announcements', x.id, x.toJson(), a, 'announcement.${x.status.name}', x.title);

  @override
  Future<void> saveExam(Exam e, Actor a) => _save('exams', e.id, e.toJson(), a, 'exam.save', e.subjectName);

  @override
  Future<void> deleteExam(String id, Actor a) {
    final (batch, _) = _batchWithAudit(a, 'exam.delete', 'exams/$id');
    batch.delete(_c('exams').doc(id));
    return batch.commit();
  }

  @override
  Future<void> saveCalendarEvent(CalendarEvent e, Actor a) => _save('calendarEvents', e.id, e.toJson(), a, 'calendar.save', e.title);

  @override
  Future<void> deleteCalendarEvent(String id, Actor a) {
    final (batch, _) = _batchWithAudit(a, 'calendar.delete', 'calendarEvents/$id');
    batch.delete(_c('calendarEvents').doc(id));
    return batch.commit();
  }

  @override
  Future<List<AdminAccount>> listAdmins() async => (await _c('admins').get()).docs
      .map(
        (d) => AdminAccount(
          d.id,
          d.data()['email'] as String? ?? '',
          AdminRole.parse(d.data()['role'] as String?),
        ),
      )
      .toList();

  @override
  Future<void> setAdmin(String uid, String email, AdminRole? role, Actor actor) {
    if (uid == actor.uid) throw const RepositoryException('You cannot change your own role.');
    final (batch, auditId) = _batchWithAudit(actor, role == null ? 'admin.revoke' : 'admin.grant', 'admins/$uid', role?.name);
    final ref = _c('admins').doc(uid);
    role == null ? batch.delete(ref) : batch.set(ref, {'email': email, 'role': role.name, 'updatedBy': actor.uid, 'auditId': auditId});
    return batch.commit();
  }

  @override
  Future<List<AuditRecord>> listAudit({int limit = 100}) async => (await _c(
    'auditLogs',
  ).orderBy('serverAt', descending: true).limit(limit).get()).docs.map((d) => AuditRecord.fromJson({...d.data(), 'id': d.id})).toList();
}
