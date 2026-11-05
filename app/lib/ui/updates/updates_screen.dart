import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'announcement_detail.dart';

class UpdatesScreen extends StatefulWidget {
  final ValueNotifier<int> tabIndex;
  const UpdatesScreen({super.key, required this.tabIndex});
  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.tabIndex.value);

  @override
  void initState() {
    super.initState();
    widget.tabIndex.addListener(_sync);
  }

  void _sync() => _tabs.animateTo(widget.tabIndex.value);

  @override
  void dispose() {
    widget.tabIndex.removeListener(_sync);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Updates', style: t.textTheme.headlineSmall),
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Announcements'),
              Tab(text: 'Exams'),
              Tab(text: 'Calendar'),
            ],
          ),
          const SizedBox(height: Gap.s),
          const StatusBanner(),
          Expanded(
            child: TabBarView(controller: _tabs, children: const [_AnnouncementsTab(), _ExamsTab(), _CalendarTab()]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- announcements --
class _AnnouncementsTab extends StatefulWidget {
  const _AnnouncementsTab();
  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  String _query = '';
  String _category = 'all';
  String _filter = 'active'; // active | saved | expired
  bool _byDeadline = true;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final now = DateTime.now();
    final base = _filter == 'saved' ? s.saved.values.toList() : s.visibleAnnouncements;
    final categories = {'all', ...base.map((a) => a.category)}.toList();
    final items =
        base.where((a) {
          final timing = a.timing(now);
          if (_filter == 'active' && timing == 'expired') return false;
          if (_filter == 'expired' && timing != 'expired') return false;
          if (_category != 'all' && a.category != _category) return false;
          final q = _query.toLowerCase();
          return q.isEmpty || a.title.toLowerCase().contains(q) || (a.description ?? '').toLowerCase().contains(q);
        }).toList()..sort(
          (a, b) => _byDeadline
              ? (a.endDate ?? DateTime(9999)).compareTo(b.endDate ?? DateTime(9999))
              : (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
        );

    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.xl),
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(hintText: 'Search announcements', prefixIcon: Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: Gap.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in const [('active', 'Current'), ('saved', 'Saved'), ('expired', 'Expired')])
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.s),
                    child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                  ),
                const SizedBox(width: Gap.s),
                PopupMenuButton<String>(
                  tooltip: 'Category',
                  onSelected: (v) => setState(() => _category = v),
                  itemBuilder: (_) => [for (final c in categories) PopupMenuItem(value: c, child: Text(_cap(c)))],
                  child: Chip(avatar: const Icon(Icons.filter_list_rounded, size: 18), label: Text(_cap(_category))),
                ),
                const SizedBox(width: Gap.s),
                ActionChip(
                  avatar: const Icon(Icons.sort_rounded, size: 18),
                  label: Text(_byDeadline ? 'By deadline' : 'Newest'),
                  onPressed: () => setState(() => _byDeadline = !_byDeadline),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.m),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xl),
              child: EmptyState(
                icon: _filter == 'saved' ? Icons.bookmark_border_rounded : Icons.campaign_outlined,
                title: _filter == 'saved' ? 'Nothing saved yet' : 'No announcements',
                message: _filter == 'saved'
                    ? 'Tap the bookmark on an announcement to keep it available offline.'
                    : (s.visibleAnnouncements.isEmpty
                          ? 'No announcements have been published for your group yet.'
                          : 'No announcements match your filters.'),
              ),
            )
          else
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: AnnouncementTile(announcement: a, now: now),
              ),
          if (s.isDemo && s.visibleAnnouncements.isEmpty)
            Text(
              'Three announcements (India Space Lab internship, ICPC India Regionals 2026, Qiskit Fall Fest 2026) are stored as admin drafts '
              'because their dates and links were not available. They appear here once an administrator completes and publishes them.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : (s == 'all' ? 'All categories' : s[0].toUpperCase() + s.substring(1));

class AnnouncementTile extends StatelessWidget {
  final Announcement announcement;
  final DateTime now;
  const AnnouncementTile({super.key, required this.announcement, required this.now});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final a = announcement;
    final timing = a.timing(now);
    final color = switch (timing) {
      'expired' => CsColors.unavailable,
      'upcoming' => CsColors.seed,
      _ => CsColors.mint,
    };
    return SectionCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnnouncementDetail(announcement: a))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    Pill(_cap(a.category), color: t.colorScheme.primary),
                    if (timing != 'undated') Pill(_cap(timing), color: color),
                  ],
                ),
                const SizedBox(height: Gap.s),
                Text(a.title, style: t.textTheme.titleSmall),
                if (a.summary != null) ...[
                  const SizedBox(height: 2),
                  Text(a.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                ],
                if (a.endDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ends ${DateFormat('d MMM yyyy').format(a.endDate!)}',
                    style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: s.isSaved(a.id) ? 'Remove from saved' : 'Save for offline',
            icon: Icon(s.isSaved(a.id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: t.colorScheme.primary),
            onPressed: () => s.toggleSaved(a),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ exams --
class _ExamsTab extends StatelessWidget {
  const _ExamsTab();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final today = dateOnly(DateTime.now());
    final exams = s.myExams;
    final upcoming = exams.where((e) => !e.date.isBefore(today)).toList();
    final past = exams.where((e) => e.date.isBefore(today)).toList();
    final window = s.data?.termEndExamWindow;
    final unchosen = s.unchosenElectiveSlots;
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.xl),
        children: [
          if (window != null && !window.end.isBefore(today))
            SectionCard(
              color: const Color(0xFF2BA8D8).withValues(alpha: 0.1),
              child: Row(
                children: [
                  _Countdown(days: window.start.isAfter(today) ? window.start.difference(today).inDays : 0),
                  const SizedBox(width: Gap.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${window.title} window', style: t.textTheme.titleSmall),
                        Text(
                          '${DateFormat('d MMM').format(window.start)} – ${DateFormat('d MMM yyyy').format(window.end)} (academic calendar)',
                          style: t.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (unchosen.isNotEmpty) ...[
            const SizedBox(height: Gap.s),
            SectionCard(
              color: CsColors.lilac.withValues(alpha: 0.12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, color: Color(0xFF7B61E0)),
                  const SizedBox(width: Gap.m),
                  Expanded(
                    child: Text(
                      'Choose your ${unchosen.join(' and ')} elective under Me → Academic profile to see '
                      '${unchosen.length == 1 ? 'its' : 'their'} exam date and time.',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.m),
          if (exams.isEmpty)
            const EmptyState(
              icon: Icons.edit_note_rounded,
              title: 'No exams published for you',
              message: 'No published final exams match your academic group or chosen electives.',
            )
          else ...[
            for (final e in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: _ExamCard(exam: e, today: today),
              ),
            if (past.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.s),
                child: Text('Completed', style: t.textTheme.titleSmall),
              ),
              for (final e in past)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.s),
                  child: _ExamCard(exam: e, today: today),
                ),
            ],
            const SizedBox(height: Gap.s),
            Text(
              'Source: official Odd Semester Final Examination Timetable 2026-27 (issued 1 Oct 2026). Exam rooms are not listed in the source.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  final Exam exam;
  final DateTime today;
  const _ExamCard({required this.exam, required this.today});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = exam;
    final time = e.startMin != null && e.endMin != null ? '${formatHm12(e.startMin!)} – ${formatHm12(e.endMin!)}' : 'Time not specified';
    return SectionCard(
      onTap: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.subjectName, style: t.textTheme.titleLarge),
                const SizedBox(height: Gap.m),
                InfoRow(Icons.event_rounded, 'Date', DateFormat('EEEE, d MMMM yyyy').format(e.date)),
                InfoRow(Icons.schedule_rounded, 'Time', '$time${e.timeSource == 'page default' ? ' (page default time)' : ''}'),
                if (e.officialCode != null) InfoRow(Icons.tag, 'Course code', e.officialCode!),
                if (e.stream != null) InfoRow(Icons.account_tree_outlined, 'Listed under', e.stream!),
                InfoRow(Icons.meeting_room_outlined, 'Room', e.room ?? 'Not listed in the source'),
                if (e.source != null) InfoRow(Icons.source_outlined, 'Source', e.source!),
                if (e.reviewFlags.isNotEmpty) InfoRow(Icons.flag_outlined, 'Note', e.reviewFlags.join(' ')),
              ],
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          _Countdown(days: e.date.difference(today).inDays),
          const SizedBox(width: Gap.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.subjectName, style: t.textTheme.titleSmall)),
                    if (e.electiveOfferingIds.isNotEmpty) Pill(e.subjectCode, color: const Color(0xFF7B61E0)),
                  ],
                ),
                Text('${DateFormat('EEE d MMM yyyy').format(e.date)} · $time', style: t.textTheme.bodySmall),
                if (e.officialCode != null)
                  Text(e.officialCode!, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  final int days;
  const _Countdown({required this.days});
  @override
  Widget build(BuildContext context) {
    final past = days < 0;
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (past ? CsColors.unavailable : const Color(0xFF2BA8D8)).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: past
          ? const Icon(Icons.check_rounded)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$days', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(days == 1 ? 'day' : 'days', style: const TextStyle(fontSize: 10)),
              ],
            ),
    );
  }
}

// --------------------------------------------------------------- calendar --
class _CalendarTab extends StatefulWidget {
  const _CalendarTab();
  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  String _audience = 'btech-mbatech-year2to6';
  String _term = 'odd';

  static const _icons = {
    'term': Icons.flag_rounded,
    'midterm': Icons.quiz_rounded,
    'termEndExam': Icons.edit_note_rounded,
    'labExam': Icons.science_rounded,
    'reExam': Icons.replay_rounded,
    'vacation': Icons.beach_access_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final d = s.data;
    if (d == null) return const SizedBox.shrink();
    final today = dateOnly(DateTime.now());
    final events =
        d.calendarEvents.where((e) => e.audience == _audience && (e.term == _term || (_term == 'even' && e.term == 'next'))).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.xl),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _audience,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Programme group'),
          items: [
            for (final e in d.calendarAudienceLabels.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _audience = v ?? _audience),
        ),
        const SizedBox(height: Gap.s),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'odd', label: Text('Odd sem · Term I')),
            ButtonSegment(value: 'even', label: Text('Even sem · Term II')),
          ],
          selected: {_term},
          onSelectionChanged: (v) => setState(() => _term = v.first),
        ),
        const SizedBox(height: Gap.m),
        if (events.isEmpty)
          const EmptyState(icon: Icons.event_note_rounded, title: 'No events', message: 'No calendar entries for this selection.')
        else
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.s),
              child: Builder(
                builder: (context) {
                  final status = e.end.isBefore(today) ? 'Done' : (e.start.isAfter(today) ? 'Upcoming' : 'Ongoing');
                  final c = status == 'Done' ? CsColors.unavailable : (status == 'Ongoing' ? CsColors.mint : CsColors.seed);
                  return SectionCard(
                    child: Row(
                      children: [
                        Icon(_icons[e.category] ?? Icons.event_rounded, color: c),
                        const SizedBox(width: Gap.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.title, style: t.textTheme.titleSmall),
                              Text(
                                e.start == e.end
                                    ? DateFormat('EEE d MMM yyyy').format(e.start)
                                    : '${DateFormat('d MMM yyyy').format(e.start)} – ${DateFormat('d MMM yyyy').format(e.end)}',
                                style: t.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Pill(status, color: c),
                      ],
                    ),
                  );
                },
              ),
            ),
        const SizedBox(height: Gap.s),
        Text(
          'Source: Academic Calendar AY 2026-27. Dates are subject to change; reconfirm before booking tickets.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
