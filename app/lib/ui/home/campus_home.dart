import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../domain/focus.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../updates/announcement_detail.dart';
import '../widgets/common.dart';
import '../world/building_interior.dart';
import '../world/character.dart';
import '../world/library_study.dart';
import 'campus_world.dart';
import 'home_shell.dart';

class CampusHome extends StatelessWidget {
  const CampusHome({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final nav = ShellNav.of(context);
    final now = DateTime.now();
    final night = now.hour >= 19 || now.hour < 6;
    final announcements = s.visibleAnnouncements.where((a) => a.timing(now) != 'expired').toList();
    final media = MediaQuery.of(context);
    final worldHeight = (media.size.width * 1.02).clamp(320.0, 460.0) + media.padding.top;
    const sheetLip = 28.0;

    return ColoredBox(
      color: t.scaffoldBackgroundColor,
      child: RefreshIndicator(
        onRefresh: s.refresh,
        edgeOffset: media.padding.top,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: worldHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      bottom: sheetLip - 4,
                      child: Padding(
                        padding: EdgeInsets.only(top: media.padding.top + 36),
                        child: CampusWorld(
                          reduceMotion: s.prefs.reduceMotion,
                          night: night,
                          avatar: s.profile?.avatar,
                          characterColor: characterColors[s.prefs.characterColor % characterColors.length],
                          focusing: s.activeFocus?.status == FocusStatus.running,
                          destinations: [
                            // Buildings with interiors: the character walks in.
                            CampusDestination(
                              id: 'classrooms',
                              label: 'Academic Block',
                              icon: Icons.apartment_rounded,
                              color: CsColors.seed,
                              onOpen: () => Navigator.push(context, enterRoute(const BuildingInteriorScreen())),
                            ),
                            CampusDestination(
                              id: 'library',
                              label: 'Library · 7F',
                              icon: Icons.menu_book_rounded,
                              color: const Color(0xFF3CA37A),
                              badge: s.activeFocus != null ? '●' : null,
                              onOpen: () => Navigator.push(context, enterRoute(const LibraryStudyScreen())),
                            ),
                            CampusDestination(
                              id: 'timetable',
                              label: 'Timetable',
                              icon: Icons.schedule_rounded,
                              color: const Color(0xFF8E73F0),
                              onOpen: () => nav.go(1),
                            ),
                            CampusDestination(
                              id: 'exams',
                              label: 'Exams',
                              icon: Icons.edit_note_rounded,
                              color: const Color(0xFF2B8FD0),
                              onOpen: () => nav.go(3, updatesTab: 1),
                            ),
                            CampusDestination(
                              id: 'notices',
                              label: 'Notices',
                              icon: Icons.campaign_rounded,
                              color: const Color(0xFFD0773F),
                              badge: announcements.isEmpty ? null : '${announcements.length}',
                              onOpen: () => nav.go(3, updatesTab: 0),
                            ),
                            CampusDestination(
                              id: 'calendar',
                              label: 'Calendar',
                              icon: Icons.celebration_rounded,
                              color: const Color(0xFFE5674A),
                              onOpen: () => nav.go(3, updatesTab: 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Sky tint behind the header so it reads over the world.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: media.padding.top + 36,
                      child: ColoredBox(color: night ? const Color(0xFF1F2156) : const Color(0xFF9CC2FF)),
                    ),
                    Positioned(
                      top: media.padding.top + 8,
                      left: 12,
                      right: 12,
                      child: _Header(state: s, night: night),
                    ),
                    // Rounded lip of the info sheet overlapping the world.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: sheetLip,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.scaffoldBackgroundColor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(color: t.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.xl),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Today on campus', style: t.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        DateFormat('EEE, d MMM').format(now),
                        style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap a building to explore, or check what is next.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Gap.m),
                  if (s.offline && s.error != null) ...[const StatusBanner(), const SizedBox(height: Gap.s)],
                  if (s.data == null)
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'No campus data yet',
                      message: s.error ?? 'Pull down to try again.',
                      action: FilledButton(onPressed: s.refresh, child: const Text('Retry')),
                    )
                  else ...[
                    if (s.activeFocus != null) ...[_FocusTile(state: s, now: now), const SizedBox(height: Gap.s)],
                    _NextClassTile(state: s, now: now),
                    const SizedBox(height: Gap.s),
                    _ComingUpTile(state: s, now: now),
                    const SizedBox(height: Gap.s),
                    _NoticeTile(items: announcements),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AppState state;
  final bool night;
  const _Header({required this.state, required this.night});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = state.profile;
    final first = (p?.displayName.trim().isNotEmpty ?? false) ? p!.displayName.trim().split(' ').first : 'Student';
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: night ? 0.88 : 0.92),
              borderRadius: BorderRadius.circular(99),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AvatarBubble(p?.avatar ?? 'fox', size: 36, selected: true),
                const SizedBox(width: Gap.s),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hi, $first',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF23233A)),
                      ),
                      Text(
                        state.myGroup?.label ?? 'No group assigned',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelSmall?.copyWith(color: const Color(0xFF5B5B76)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Gap.s),
        if (state.refreshing)
          const Padding(
            padding: EdgeInsets.all(6),
            child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          ),
        if (state.isDemo || state.environmentNote != null)
          // Visible disclosure; tap for the full explanation.
          Tooltip(
            message: state.environmentNote ?? 'Demo mode: showing the bundled reference data; nothing is saved to a server.',
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: const Color(0xFF2A2A40).withValues(alpha: 0.78), borderRadius: BorderRadius.circular(99)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.science_outlined, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    state.isDemo ? 'Demo data' : 'Test env',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Shared tile for the "Today on campus" panel.
class _InfoTile extends StatelessWidget {
  final Color color;
  final Widget leading;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? footer;
  final VoidCallback onTap;
  const _InfoTile({
    required this.color,
    required this.leading,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.cardTheme.color,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.22), width: 1.2),
          ),
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.s, Gap.m),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
                child: leading,
              ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: t.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 2),
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium?.copyWith(height: 1.2)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    if (footer != null) ...[const SizedBox(height: Gap.s), footer!],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

String _until(Duration d) {
  if (d.inMinutes < 60) return 'in ${d.inMinutes} min';
  if (d.inHours < 24) return 'in ${d.inHours} h ${d.inMinutes % 60} min';
  return 'in ${d.inDays} day${d.inDays == 1 ? '' : 's'}';
}

/// Re-renders every second so the remaining time counts down on the Campus tab.
class _FocusTile extends StatefulWidget {
  final AppState state;
  final DateTime now;
  const _FocusTile({required this.state, required this.now});
  @override
  State<_FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<_FocusTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      widget.state.settleFocus();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final now = state.clock();
    final f = state.activeFocus;
    if (f == null) return const SizedBox.shrink();
    final paused = f.status == FocusStatus.paused;
    const color = Color(0xFF3CA37A);
    return _InfoTile(
      color: color,
      leading: const Icon(Icons.menu_book_rounded, color: color),
      eyebrow: paused ? 'FOCUS SESSION · PAUSED' : 'FOCUS SESSION',
      title: '${formatRemaining(f.remainingAt(now))} left',
      subtitle: 'Library · Floor 7 · ${f.plannedMinutes}-minute session',
      onTap: () => Navigator.push(context, enterRoute(const LibraryStudyScreen())),
    );
  }
}

class _NextClassTile extends StatelessWidget {
  final AppState state;
  final DateTime now;
  const _NextClassTile({required this.state, required this.now});

  @override
  Widget build(BuildContext context) {
    final nav = ShellNav.of(context);
    final svc = state.schedule;
    final p = state.scheduleProfile;
    final d = state.data!;
    final next = (svc != null && p != null) ? svc.nextClass(p, now) : null;
    if (next == null) {
      return _InfoTile(
        color: CsColors.mint,
        leading: const Icon(Icons.event_available_rounded, color: CsColors.mint),
        eyebrow: 'NEXT CLASS',
        title: p != null && svc != null && !svc.hasTimetable(p, now)
            ? 'No published timetable covers today'
            : 'No classes in the next 7 days',
        onTap: () => nav.go(1),
      );
    }
    final e = next.entry;
    final color = CsColors.forSubject(e.subjectCode);
    final nowMin = now.hour * 60 + now.minute;
    final room = e.roomId != null ? d.roomDisplay(e.roomId) : (e.kind == EntryKind.elective ? 'Room per elective' : 'Room not listed');
    final day = DateUtils.isSameDay(next.start, now) ? 'Today' : DateFormat('EEE d MMM').format(next.start);
    return _InfoTile(
      color: color,
      leading: Text(
        e.subjectCode ?? '?',
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13),
      ),
      eyebrow: next.inProgress ? 'IN PROGRESS' : 'NEXT CLASS · ${_until(next.start.difference(now)).toUpperCase()}',
      title: d.subjectName(e),
      subtitle: '$day · ${formatHm12(e.startMin)}–${formatHm12(e.endMin)} · $room',
      footer: next.inProgress
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ((nowMin - e.startMin) / e.durationMin).clamp(0.0, 1.0),
                minHeight: 5,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            )
          : null,
      onTap: () => nav.go(1),
    );
  }
}

class _ComingUpTile extends StatelessWidget {
  final AppState state;
  final DateTime now;
  const _ComingUpTile({required this.state, required this.now});

  @override
  Widget build(BuildContext context) {
    final nav = ShellNav.of(context);
    final today = dateOnly(now);
    final exam = state.myExams.where((e) => !e.date.isBefore(today)).firstOrNull;
    final events =
        (state.data?.calendarEvents ?? const <CalendarEvent>[])
            .where((e) => e.audience == 'btech-mbatech-year2to6' && !e.end.isBefore(today) && e.category != 'term')
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final ev = events.firstOrNull;
    const color = Color(0xFF2B8FD0);
    Widget countdown(int days) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$days',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color, height: 1),
        ),
        Text(days == 1 ? 'day' : 'days', style: const TextStyle(fontSize: 10, color: color)),
      ],
    );
    if (exam != null) {
      return _InfoTile(
        color: color,
        leading: countdown(exam.date.difference(today).inDays),
        eyebrow: 'UPCOMING EXAM',
        title: exam.subjectName,
        subtitle: '${DateFormat('EEE d MMM').format(exam.date)}${exam.startTime != null ? ' · ${exam.startTime}' : ''}',
        onTap: () => nav.go(3, updatesTab: 1),
      );
    }
    if (ev != null) {
      final days = ev.start.isAfter(today) ? ev.start.difference(today).inDays : 0;
      return _InfoTile(
        color: color,
        leading: countdown(days),
        eyebrow: 'COMING UP · ACADEMIC CALENDAR',
        title: ev.title,
        subtitle: '${DateFormat('d MMM').format(ev.start)} – ${DateFormat('d MMM yyyy').format(ev.end)}',
        onTap: () => nav.go(3, updatesTab: 2),
      );
    }
    return _InfoTile(
      color: color,
      leading: const Icon(Icons.edit_calendar_rounded, color: color),
      eyebrow: 'COMING UP',
      title: 'No upcoming exams or calendar events',
      onTap: () => nav.go(3, updatesTab: 2),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  final List<Announcement> items;
  const _NoticeTile({required this.items});

  @override
  Widget build(BuildContext context) {
    final nav = ShellNav.of(context);
    final a = items.firstOrNull;
    const color = Color(0xFFC77A2E);
    return _InfoTile(
      color: color,
      leading: const Icon(Icons.campaign_rounded, color: color),
      eyebrow: items.length > 1 ? 'NOTICE BOARD · ${items.length} ACTIVE' : 'NOTICE BOARD',
      title: a?.title ?? 'No announcements published yet',
      subtitle: a?.endDate != null
          ? 'Ends ${DateFormat('d MMM yyyy').format(a!.endDate!)}'
          : (a == null ? 'New notices will appear here once published.' : null),
      onTap: a == null
          ? () => nav.go(3, updatesTab: 0)
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnnouncementDetail(announcement: a))),
    );
  }
}
