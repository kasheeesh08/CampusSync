import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../domain/timetable_validator.dart';
import '../onboarding/auth_screens.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_catalog.dart';
import 'admin_content.dart';
import 'admin_people.dart';
import 'admin_timetables.dart';

/// Runs an admin write with consistent feedback and a data refresh.
Future<bool> adminAction(BuildContext context, Future<void> Function() op, {required String success}) async {
  final s = context.read<AppState>();
  try {
    await op();
    await s.refresh();
    if (context.mounted) showMessage(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, 'Failed: $e', error: true);
    return false;
  }
}

class AdminGate extends StatelessWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.user == null) return const _AdminSignIn();
    if (s.adminRole == null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Access denied',
          message: '${s.user!.email} is not an authorised administrator.',
          action: FilledButton(onPressed: s.signOut, child: const Text('Sign out')),
        ),
      );
    }
    return const AdminShell();
  }
}

class _AdminSignIn extends StatelessWidget {
  const _AdminSignIn();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings_rounded, size: 64, color: t.colorScheme.primary),
              const SizedBox(height: Gap.l),
              Text('CampusSync Admin', style: t.textTheme.headlineSmall),
              const SizedBox(height: Gap.s),
              const Text('Sign in with an administrator account.'),
              const SizedBox(height: Gap.xl),
              FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInScreen())),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section {
  final String label;
  final IconData icon;
  final Widget Function() build;
  final bool fullAdminOnly;
  const _Section(this.label, this.icon, this.build, {this.fullAdminOnly = true});
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  // Optional deep link, e.g. ?section=timetables, for bookmarking a page.
  int _index = _initialIndex();

  static int _initialIndex() {
    final wanted = Uri.base.queryParameters['section']?.toLowerCase();
    if (wanted == null) return 0;
    final i = _all.indexWhere((x) => x.label.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-').startsWith(wanted));
    return i < 0 ? 0 : i;
  }

  static final _all = <_Section>[
    _Section('Overview', Icons.dashboard_rounded, () => const AdminOverview(), fullAdminOnly: false),
    _Section('Timetables', Icons.calendar_view_week_rounded, () => const AdminTimetables()),
    _Section('Academic groups', Icons.account_tree_rounded, () => const AdminGroups()),
    _Section('Rooms & floors', Icons.meeting_room_rounded, () => const AdminRooms()),
    _Section('Announcements', Icons.campaign_rounded, () => const AdminAnnouncements(), fullAdminOnly: false),
    _Section('Exams & calendar', Icons.event_note_rounded, () => const AdminExamsCalendar(), fullAdminOnly: false),
    _Section('Students', Icons.school_rounded, () => const AdminStudents()),
    _Section('Administrators', Icons.admin_panel_settings_rounded, () => const AdminAdmins()),
    _Section('Audit log', Icons.history_rounded, () => const AdminAudit(), fullAdminOnly: false),
    _Section('Settings', Icons.tune_rounded, () => const AdminSettings()),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final sections = _all.where((x) => s.adminRole == AdminRole.admin || !x.fullAdminOnly).toList();
    final index = _index.clamp(0, sections.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = Column(
      children: [
        if (s.isDemo)
          Container(
            width: double.infinity,
            color: t.colorScheme.primaryContainer,
            padding: const EdgeInsets.all(Gap.s),
            child: const Text(
              'Demo mode: Firebase is not configured. Changes stay in this browser session only and are not published to students.',
              textAlign: TextAlign.center,
            ),
          ),
        if (s.environmentNote != null)
          Container(
            width: double.infinity,
            color: CsColors.partial.withValues(alpha: 0.2),
            padding: const EdgeInsets.all(Gap.s),
            child: Text(s.environmentNote!, textAlign: TextAlign.center),
          ),
        if (s.error != null && !s.isDemo)
          Container(
            width: double.infinity,
            color: t.colorScheme.errorContainer,
            padding: const EdgeInsets.all(Gap.s),
            child: Text(s.error!, textAlign: TextAlign.center),
          ),
        Expanded(child: s.data == null ? const Center(child: CircularProgressIndicator()) : sections[index].build()),
      ],
    );
    final destinations = [for (final x in sections) (x.label, x.icon)];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.school_rounded, color: t.colorScheme.primary),
            const SizedBox(width: Gap.s),
            const Flexible(child: Text('CampusSync Admin', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          if (s.refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(tooltip: 'Reload data', onPressed: s.refresh, icon: const Icon(Icons.refresh_rounded)),
          if (MediaQuery.sizeOf(context).width >= 700)
            Center(child: Text('${s.user?.email ?? ''} · ${s.adminRole?.name ?? ''}', style: t.textTheme.bodySmall)),
          if (!s.isDemo) IconButton(tooltip: 'Sign out', onPressed: s.signOut, icon: const Icon(Icons.logout_rounded)),
          const SizedBox(width: Gap.s),
        ],
      ),
      drawer: wide
          ? null
          : NavigationDrawer(
              selectedIndex: index,
              onDestinationSelected: (i) {
                setState(() => _index = i);
                Navigator.pop(context);
              },
              children: [
                const SizedBox(height: Gap.l),
                for (final d in destinations) NavigationDrawerDestination(icon: Icon(d.$2), label: Text(d.$1)),
              ],
            ),
      body: wide
          ? Row(
              children: [
                // Scrollable so all sections stay reachable in short browser windows.
                LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: IntrinsicHeight(
                        child: NavigationRail(
                          extended: MediaQuery.sizeOf(context).width >= 1200,
                          selectedIndex: index,
                          onDestinationSelected: (i) => setState(() => _index = i),
                          labelType: MediaQuery.sizeOf(context).width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                          destinations: [for (final d in destinations) NavigationRailDestination(icon: Icon(d.$2), label: Text(d.$1))],
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }
}

/// Common page frame for admin sections.
class AdminPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  const AdminPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: Gap.s,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.textTheme.headlineSmall),
                  if (subtitle != null) Text(subtitle!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ],
              ),
              Wrap(spacing: Gap.s, children: actions),
            ],
          ),
          const SizedBox(height: Gap.l),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AdminOverview extends StatelessWidget {
  const AdminOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final today = DateTime.now();
    final coverage = d.availability.coverageOn(today);
    final validator = TimetableValidator(
      rooms: d.rooms,
      subjectCodes: d.subjects.map((x) => x.code),
      facultyIds: d.faculty.map((f) => f.id),
      settings: d.settings,
    );
    final published = d.versions.where((v) => v.status == VersionStatus.published).toList();
    final results = {
      for (final v in published)
        v: validator.validate(v, group: d.groupsById[v.groupId], otherPublished: published, groupsById: d.groupsById),
    };
    Widget stat(String label, String value, IconData icon, Color c) => SizedBox(
      width: 220,
      child: SectionCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: c.withValues(alpha: 0.15),
              child: Icon(icon, color: c),
            ),
            const SizedBox(width: Gap.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: t.textTheme.headlineSmall),
                  Text(label, style: t.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return AdminPage(
      title: 'Overview',
      subtitle: d.institutionName,
      child: ListView(
        children: [
          Wrap(
            spacing: Gap.m,
            runSpacing: Gap.m,
            children: [
              stat('Active groups', '${d.groups.where((g) => g.active).length}', Icons.account_tree_rounded, CsColors.seed),
              stat('Published timetables', '${published.length}', Icons.calendar_view_week_rounded, CsColors.mint),
              stat(
                'Draft timetables',
                '${d.versions.where((v) => v.status == VersionStatus.draft).length}',
                Icons.edit_calendar_rounded,
                CsColors.partial,
              ),
              stat('Rooms', '${d.rooms.length}', Icons.meeting_room_rounded, CsColors.lilac),
              stat(
                'Announcements (draft)',
                '${d.announcements.where((a) => a.status == PublishStatus.draft).length}',
                Icons.campaign_rounded,
                CsColors.coral,
              ),
              stat('Exams', '${d.exams.length}', Icons.edit_note_rounded, const Color(0xFF2BA8D8)),
            ],
          ),
          const SizedBox(height: Gap.xl),
          Text('Room-availability coverage today', style: t.textTheme.titleMedium),
          const SizedBox(height: Gap.s),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(coverage.describe()),
                const SizedBox(height: Gap.s),
                Text(
                  d.settings.coverageDeclaredComplete
                      ? 'Coverage is declared complete: rooms with no class are shown to students as verified free.'
                      : 'Coverage is NOT declared complete: students see "No class listed · unverified" instead of "free". Change this in Settings once every department\'s timetable is uploaded.',
                  style: t.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          Text('Published timetable health', style: t.textTheme.titleMedium),
          const SizedBox(height: Gap.s),
          for (final e in results.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.s),
              child: SectionCard(
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(d.groupsById[e.key.groupId]?.label ?? e.key.groupId),
                  subtitle: Text('v${e.key.version} · ${e.value.errors.length} error(s), ${e.value.warnings.length} warning(s)'),
                  children: [
                    for (final i in e.value.issues.take(40))
                      ListTile(
                        dense: true,
                        leading: Icon(
                          i.level == IssueLevel.error ? Icons.error_outline : Icons.warning_amber_rounded,
                          color: i.level == IssueLevel.error ? t.colorScheme.error : CsColors.partial,
                        ),
                        title: Text(i.message),
                        subtitle: i.entryId != null ? Text(i.entryId!) : null,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
