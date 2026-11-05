import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/auth_service.dart';
import '../data/campus_data.dart';
import '../data/focus_repository.dart';
import '../data/local_cache.dart';
import '../data/registration_errors.dart';
import '../data/repository.dart';
import '../domain/focus.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';
import '../domain/schedule.dart';
import '../services/notification_service.dart';

enum SessionStage { loading, signedOut, verifyEmail, pendingApproval, suspended, needsProfile, ready }

/// Registration details typed before the email is verified. Kept in memory
/// only; the profile and SAP ID claim are written after verification, because
/// the security rules accept them only from a verified account.
class RegistrationDraft {
  final String displayName;
  final String sapId;
  final String rollNumber;
  final String requestedGroupId;
  final String? batch;
  const RegistrationDraft({
    required this.displayName,
    required this.sapId,
    required this.rollNumber,
    required this.requestedGroupId,
    this.batch,
  });
}

/// Application-wide state shared by the student app and the admin dashboard.
class AppState extends ChangeNotifier {
  final CampusRepository repo;
  final AuthService? auth; // null in demo mode
  final LocalCache cache;
  final NotificationService notifications;
  final bool adminApp;

  /// Shown in every screen's status banner (e.g. emulator/test environment).
  final String? environmentNote;

  AppState({
    required this.repo,
    required this.auth,
    required this.cache,
    required this.notifications,
    this.adminApp = false,
    this.environmentNote,
    FocusRepository? focusRepo,
    DateTime Function()? clock,
  }) : focusRepo = focusRepo ?? LocalFocusRepository(cache.prefs),
       clock = clock ?? DateTime.now;

  // ---------------------------------------------------------------- focus --
  /// Device-local study sessions (see [FocusRepository.storageLabel]).
  final FocusRepository focusRepo;

  /// Injectable clock so session timing can be tested deterministically.
  final DateTime Function() clock;
  FocusSession? activeFocus;
  FocusSession? lastFinishedFocus; // shown as the completion state until dismissed
  List<FocusSession> focusHistory = [];

  Future<void> _loadFocus() async {
    activeFocus = await focusRepo.loadActive();
    focusHistory = await focusRepo.history();
    await settleFocus();
  }

  /// Applies the clock (e.g. after the app was backgrounded or closed).
  Future<void> settleFocus() async {
    final s = activeFocus;
    if (s == null) return;
    final settled = s.settle(clock());
    if (settled.status == FocusStatus.completed) await _finishFocus(settled);
  }

  Future<void> _finishFocus(FocusSession done) async {
    activeFocus = null;
    lastFinishedFocus = done;
    await focusRepo.saveActive(null);
    await focusRepo.addToHistory(done);
    focusHistory = await focusRepo.history();
    notifyListeners();
    unawaited(rescheduleReminders());
  }

  Future<void> startFocus({required StudySpace space, required StudySpot spot, required int minutes}) async {
    if (activeFocus != null) throw StateError('A focus session is already active.');
    activeFocus = FocusSession.start(spaceId: space.id, spotId: spot.id, minutes: minutes, now: clock());
    lastFinishedFocus = null;
    await focusRepo.saveActive(activeFocus);
    notifyListeners();
    unawaited(rescheduleReminders());
  }

  Future<void> _updateFocus(FocusSession Function(FocusSession, DateTime) op) async {
    final s = activeFocus;
    if (s == null) return;
    final next = op(s, clock());
    if (!next.isActive) return _finishFocus(next);
    activeFocus = next;
    await focusRepo.saveActive(next);
    notifyListeners();
    unawaited(rescheduleReminders());
  }

  Future<void> pauseFocus() => _updateFocus((s, now) => s.pause(now));
  Future<void> resumeFocus() => _updateFocus((s, now) => s.resume(now));
  Future<void> endFocus() => _updateFocus((s, now) => s.end(now));

  void dismissFocusResult() {
    lastFinishedFocus = null;
    notifyListeners();
  }

  bool get isDemo => repo.isDemo;

  AuthUser? user;
  StudentProfile? profile;
  AdminRole? adminRole;
  RegistrationDraft? registrationDraft;
  CampusData? data;
  bool loading = true;
  bool refreshing = false;
  bool offline = false;
  String? error;
  Map<String, Announcement> saved = {};
  AppPreferences prefs = const AppPreferences();
  int scheduledReminders = 0;
  bool notificationsBlocked = false; // Android permission off: scheduled reminders will not appear
  StreamSubscription<AuthUser?>? _authSub;

  // ------------------------------------------------------------- lifecycle --
  Future<void> init() async {
    await _loadFocus();
    prefs = cache.loadPrefs();
    saved = cache.loadSaved();
    if (isDemo) {
      profile = adminApp ? null : cache.loadProfile('demo');
      if (adminApp) adminRole = AdminRole.admin;
      user = adminApp ? const AuthUser('demo-admin', 'demo-admin@local', true) : null;
      await refresh();
      loading = false;
      notifyListeners();
      return;
    }
    // Show the last synced data immediately while auth resolves.
    if (!adminApp) data = cache.loadSnapshot();
    _authSub = auth!.changes().listen(_onAuth);
  }

  Future<void> _onAuth(AuthUser? u) async {
    user = u;
    if (u == null) {
      profile = null;
      adminRole = null;
      loading = false;
      notifyListeners();
      return;
    }
    try {
      adminRole = await repo.adminRole(u.uid);
      if (!adminApp) {
        profile = await repo.loadProfile(u.uid);
        if (profile != null) await cache.storeProfile('user', profile);
      }
      error = null;
    } catch (e) {
      // Offline: fall back to the cached profile so timetables stay readable.
      profile = cache.loadProfile('user');
      error = 'Could not reach the server. Showing your last synced data.';
      offline = true;
    }
    // Clear the loading flag first: `stage` reports "loading" while it is set,
    // which previously skipped the initial fetch for a persisted sign-in.
    loading = false;
    if (stage == SessionStage.ready) await refresh();
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  SessionStage get stage {
    if (loading) return SessionStage.loading;
    if (isDemo) return adminApp || profile != null ? SessionStage.ready : SessionStage.needsProfile;
    final u = user;
    if (u == null) return SessionStage.signedOut;
    if (adminApp) return SessionStage.ready; // dashboard checks adminRole itself
    if (adminRole != null) return SessionStage.ready;
    if (!u.emailVerified) return SessionStage.verifyEmail;
    final p = profile;
    if (p == null) return SessionStage.needsProfile;
    return switch (p.status) {
      AccountStatus.pending => SessionStage.pendingApproval,
      AccountStatus.suspended => SessionStage.suspended,
      AccountStatus.active => p.groupId == null ? SessionStage.pendingApproval : SessionStage.ready,
    };
  }

  Actor get actor => Actor(user?.uid ?? 'unknown', user?.email ?? 'unknown');

  // ------------------------------------------------------------------ data --
  Future<void> refresh() async {
    refreshing = true;
    notifyListeners();
    try {
      // Re-read the profile so admin changes (group reassignment, suspension)
      // take effect on refresh instead of only after signing in again.
      final u = user;
      if (!isDemo && !adminApp && u != null) {
        final p = await repo.loadProfile(u.uid);
        if (p != null) {
          profile = p;
          await cache.storeProfile('user', p);
        }
        if (stage != SessionStage.ready) {
          // e.g. now suspended: stop reminders and do not fetch academic data.
          await notifications.cancelAll();
          scheduledReminders = 0;
          return;
        }
      }
      final fresh = await repo.fetch(asAdmin: adminApp && adminRole != null, student: adminApp ? null : profile);
      data = fresh;
      // Firestore may answer from its device cache when offline; say so.
      offline = fresh.origin == DataOrigin.cache;
      error = offline ? 'Offline – showing data cached on this device; it may be out of date.' : null;
      if (!isDemo && !adminApp && !offline) await cache.saveSnapshot(fresh);
      await _refreshSaved(fresh);
    } catch (e) {
      final cached = adminApp ? null : cache.loadSnapshot();
      if (cached != null) data = cached;
      offline = true;
      error = cached != null
          ? 'Offline – showing data last synced ${_ago(cached.syncedAt)}.'
          : 'Could not load campus data. Check your connection and try again.';
    } finally {
      refreshing = false;
      notifyListeners();
    }
    unawaited(rescheduleReminders());
  }

  /// Keeps saved copies in sync with the server where they still exist.
  Future<void> _refreshSaved(CampusData d) async {
    var changed = false;
    for (final a in d.announcements) {
      if (saved.containsKey(a.id)) {
        saved[a.id] = a;
        changed = true;
      }
    }
    if (changed) await cache.storeSaved(saved);
  }

  static String _ago(DateTime? t) {
    if (t == null) return 'at an unknown time';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} day(s) ago';
  }

  String get syncLabel => switch (data?.origin) {
    DataOrigin.server => 'Synced ${_ago(data?.syncedAt)}',
    DataOrigin.cache => 'Offline copy from ${_ago(data?.syncedAt)}',
    DataOrigin.bundledDemo => 'Demo data bundled with the app (reference documents)',
    null => 'Not synced yet',
  };

  // -------------------------------------------------------------- schedule --
  ScheduleProfile? get scheduleProfile {
    final p = profile;
    final gid = p?.groupId;
    if (p == null || gid == null) return null;
    // A batch left over from another group (e.g. B1 after moving to Div C) is ignored.
    final batches = data?.groupsById[gid]?.batches ?? const <String>[];
    final batch = batches.contains(p.batch) ? p.batch : null;
    return ScheduleProfile(groupId: gid, batch: batch, oe1OfferingId: p.oe1OfferingId, oe2OfferingId: p.oe2OfferingId);
  }

  ScheduleService? get schedule {
    final d = data;
    if (d == null) return null;
    final pools = <String, String>{};
    for (final g in d.groups.where((g) => g.type == 'electivePool')) {
      if (g.id.startsWith('oe1')) pools['OE-1'] = g.id;
      if (g.id.startsWith('oe2')) pools['OE-2'] = g.id;
    }
    return ScheduleService(d.availability, settings: d.settings, electivePoolBySlot: pools);
  }

  AcademicGroup? get myGroup => data?.groupsById[profile?.groupId];

  List<Announcement> get visibleAnnouncements {
    final d = data;
    if (d == null) return const [];
    final g = myGroup;
    return d.announcements
        .where((a) => a.status == PublishStatus.published && a.audience.includes(groupId: g?.id, departmentId: g?.departmentId))
        .toList();
  }

  /// Published exams for the student's group plus their chosen open electives.
  List<Exam> get myExams {
    final p = profile;
    return (data?.exams ?? const <Exam>[])
        .where((e) => e.status == PublishStatus.published)
        .where((e) => e.appliesTo(groupId: p?.groupId, electiveIds: [p?.oe1OfferingId, p?.oe2OfferingId]))
        .toList()
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : (a.startMin ?? 0).compareTo(b.startMin ?? 0);
      });
  }

  /// Open-elective slots whose exam can't be shown because no elective is chosen.
  List<String> get unchosenElectiveSlots => [if (profile?.oe1OfferingId == null) 'OE-1', if (profile?.oe2OfferingId == null) 'OE-2'];

  // --------------------------------------------------------------- profile --
  Future<void> chooseDemoProfile({required String groupId, String? batch, String name = 'Guest'}) async {
    profile = StudentProfile(
      uid: 'demo',
      email: '',
      displayName: name,
      sapId: '',
      rollNumber: '',
      groupId: groupId,
      batch: batch,
      avatar: profile?.avatar ?? 'fox',
      status: AccountStatus.active,
    );
    await cache.storeProfile('demo', profile);
    notifyListeners();
    unawaited(rescheduleReminders());
  }

  Future<void> updatePreferences(Map<String, Object?> changes) async {
    final p = profile;
    if (p == null) return;
    final updated = StudentProfile.fromJson({...p.toJson(), ...changes});
    if (!isDemo) await repo.updateOwnPreferences(p.uid, changes);
    profile = updated;
    await cache.storeProfile(isDemo ? 'demo' : 'user', updated);
    notifyListeners();
    unawaited(rescheduleReminders());
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String sapId,
    required String rollNumber,
    required String requestedGroupId,
    String? batch,
  }) async {
    final a = auth!;
    final draft = RegistrationDraft(
      displayName: displayName.trim(),
      sapId: sapId.trim(),
      rollNumber: rollNumber.trim().toUpperCase(),
      requestedGroupId: requestedGroupId,
      batch: batch,
    );
    var u = user;
    if (u == null) {
      // Step 1: create the sign-in account only. The details are submitted
      // once the email is verified (step 2, the "Complete your profile" form).
      u = await a.register(email, password);
      if (!u.emailVerified) {
        registrationDraft = draft;
        notifyListeners();
        return;
      }
    } else {
      // A restored session may hold a token issued before verification.
      u = await a.reload() ?? u;
      // Never look up SAP IDs for an unverified account (the rules deny it too).
      if (!u.emailVerified) throw RegistrationException(RegistrationFailure.unverifiedEmail);
    }
    await repo.registerProfile(
      StudentProfile(
        uid: u.uid,
        email: u.email, // the verified sign-in email; the rules reject anything else
        displayName: draft.displayName,
        sapId: draft.sapId,
        rollNumber: draft.rollNumber,
        requestedGroupId: draft.requestedGroupId,
        batch: draft.batch,
      ),
    );
    registrationDraft = null;
    profile = await repo.loadProfile(u.uid);
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await auth!.signIn(email, password);
  }

  Future<void> reloadUser() async {
    final u = await auth?.reload();
    if (u != null) await _onAuth(u);
  }

  Future<void> signOut() async {
    await notifications.cancelAll();
    registrationDraft = null;
    if (isDemo) {
      profile = null;
      await cache.storeProfile('demo', null);
      notifyListeners();
      return;
    }
    await cache.clearAccountData();
    saved = {};
    data = null;
    await auth!.signOut();
  }

  // ----------------------------------------------------------------- saved --
  bool isSaved(String id) => saved.containsKey(id);

  Future<void> toggleSaved(Announcement a) async {
    saved.containsKey(a.id) ? saved.remove(a.id) : saved[a.id] = a;
    await cache.storeSaved(saved);
    notifyListeners();
    unawaited(rescheduleReminders());
  }

  // ----------------------------------------------------------------- prefs --
  Future<void> setPrefs(AppPreferences p) async {
    prefs = p;
    await cache.storePrefs(p);
    notifyListeners();
    unawaited(rescheduleReminders());
  }

  Future<void> rescheduleReminders() async {
    final d = data;
    if (d == null || adminApp || !notifications.available) return;
    await notifications.init(d.settings.timezone);
    if (!notifications.available) return;
    final s = schedule;
    final reminders = planReminders(
      now: DateTime.now(),
      schedule: s,
      profile: scheduleProfile,
      describe: d.subjectName,
      classes: prefs.classReminders,
      leadMinutes: prefs.reminderLeadMinutes,
      exams: myExams,
      examReminders: prefs.examReminders,
      deadlines: saved.values.toList(),
      deadlineReminders: prefs.deadlineReminders,
    );
    // A running focus session gets a completion reminder (kept even when the
    // app is closed). Paused sessions have no fixed end, so none is scheduled.
    final due = activeFocus?.completesAt;
    if (due != null && due.isAfter(clock())) {
      reminders.add(
        PlannedReminder(
          'focus:${activeFocus!.id}',
          'Focus session complete',
          '${activeFocus!.plannedMinutes}-minute session finished. Take a short break.',
          due,
        ),
      );
    }
    scheduledReminders = await notifications.replaceAll(reminders);
    notificationsBlocked = (await notifications.enabled()) == false;
    notifyListeners();
  }
}
