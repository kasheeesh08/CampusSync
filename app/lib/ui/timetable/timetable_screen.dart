import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/campus_data.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});
  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  late DateTime _date = _initialDate();
  bool _week = false;

  static DateTime _initialDate() {
    final d = dateOnly(DateTime.now());
    return d.weekday == DateTime.sunday ? d.add(const Duration(days: 1)) : d;
  }

  DateTime get _monday => _date.subtract(Duration(days: _date.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final data = s.data;
    final svc = s.schedule;
    final profile = s.scheduleProfile;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, Gap.s),
            child: Row(
              children: [
                Expanded(child: Text('Timetable', style: t.textTheme.headlineSmall)),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Day'), icon: Icon(Icons.view_day_outlined)),
                    ButtonSegment(value: true, label: Text('Week'), icon: Icon(Icons.view_week_outlined)),
                  ],
                  selected: {_week},
                  onSelectionChanged: (v) => setState(() => _week = v.first),
                ),
              ],
            ),
          ),
          const StatusBanner(),
          _WeekStrip(
            monday: _monday,
            selected: _date,
            showDays: !_week,
            onPrev: () => setState(() => _date = _date.subtract(const Duration(days: 7))),
            onNext: () => setState(() => _date = _date.add(const Duration(days: 7))),
            onToday: () => setState(() => _date = _initialDate()),
            onSelect: (d) => setState(() => _date = d),
          ),
          Expanded(
            child: data == null || svc == null || profile == null
                ? const EmptyState(
                    icon: Icons.event_busy_rounded,
                    title: 'Timetable unavailable',
                    message: 'Your academic group is not set yet.',
                  )
                : _week
                ? _WeekView(data: data, svc: svc, profile: profile, monday: _monday)
                : RefreshIndicator(
                    onRefresh: s.refresh,
                    child: _DayView(data: data, svc: svc, profile: profile, date: _date),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final DateTime monday;
  final DateTime selected;
  final bool showDays;
  final VoidCallback onPrev, onNext, onToday;
  final ValueChanged<DateTime> onSelect;
  const _WeekStrip({
    required this.monday,
    required this.selected,
    required this.showDays,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.s),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(tooltip: 'Previous week', onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(
                child: Text(
                  'Week of ${DateFormat('d MMM yyyy').format(monday)}',
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleSmall,
                ),
              ),
              TextButton(onPressed: onToday, child: const Text('Today')),
              IconButton(tooltip: 'Next week', onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
            ],
          ),
          if (showDays)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.s),
              child: Row(
                children: [
                  for (var i = 0; i < 6; i++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final d = monday.add(Duration(days: i));
                          final sel = DateUtils.isSameDay(d, selected);
                          final isToday = DateUtils.isSameDay(d, today);
                          return Padding(
                            padding: const EdgeInsets.all(3),
                            child: Semantics(
                              selected: sel,
                              button: true,
                              label: DateFormat('EEEE d MMMM').format(d),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => onSelect(d),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: sel ? t.colorScheme.primary : (isToday ? t.colorScheme.primaryContainer : t.cardTheme.color),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        weekdayShort[i],
                                        style: t.textTheme.labelSmall?.copyWith(color: sel ? Colors.white : t.colorScheme.onSurfaceVariant),
                                      ),
                                      Text(
                                        '${d.day}',
                                        style: t.textTheme.titleMedium?.copyWith(color: sel ? Colors.white : t.colorScheme.onSurface),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  final CampusData data;
  final ScheduleService svc;
  final ScheduleProfile profile;
  final DateTime date;
  const _DayView({required this.data, required this.svc, required this.profile, required this.date});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (date.weekday == DateTime.sunday) {
      return ListView(
        children: const [
          SizedBox(height: 60),
          EmptyState(icon: Icons.weekend_rounded, title: 'Sunday', message: 'No classes are scheduled on Sundays.'),
        ],
      );
    }
    final slots = svc.dayView(profile, date);
    if (slots.length == 1 && slots.first.type == SlotType.noTimetable) {
      return ListView(
        children: const [
          SizedBox(height: 60),
          EmptyState(
            icon: Icons.event_busy_rounded,
            title: 'No published timetable for this date',
            message:
                'This date is outside the effective period of your group\'s published timetable. '
                'Check the academic calendar for term dates.',
          ),
        ],
      );
    }
    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(now, date);
    final nowMin = now.hour * 60 + now.minute;
    final version = svc.engine.effectiveVersion(profile.groupId, date);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.l, Gap.s, Gap.l, Gap.xl),
      children: [
        Text(DateFormat('EEEE, d MMMM').format(date), style: t.textTheme.titleMedium),
        const SizedBox(height: Gap.s),
        for (final slot in slots)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.s),
            child: _SlotCard(data: data, slot: slot, live: isToday && slot.startMin <= nowMin && nowMin < slot.endMin),
          ),
        if (version != null) ...[
          const SizedBox(height: Gap.m),
          Text(
            'Source: published v${version.version}, effective ${DateFormat('d MMM yyyy').format(version.effectiveFrom)}'
            '${version.effectiveTo != null ? ' – ${DateFormat('d MMM yyyy').format(version.effectiveTo!)}' : ''}.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _SlotCard extends StatelessWidget {
  final CampusData data;
  final DaySlot slot;
  final bool live;
  const _SlotCard({required this.data, required this.slot, required this.live});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final time = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatHm12(slot.startMin), style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(formatHm12(slot.endMin), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ],
    );
    final e = slot.entry;
    Widget body;
    Color accent;
    switch (slot.type) {
      case SlotType.noEntry:
        accent = t.colorScheme.outlineVariant;
        body = Text(
          'No class listed in the source timetable',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
        );
      case SlotType.freePeriod:
        accent = CsColors.mint;
        body = Row(
          children: [
            Icon(e!.kind == EntryKind.library ? Icons.local_library_rounded : Icons.coffee_rounded, color: CsColors.mint, size: 20),
            const SizedBox(width: Gap.s),
            Flexible(
              child: Text(e.kind == EntryKind.library ? 'Library · free period' : 'Break · free period', style: t.textTheme.titleSmall),
            ),
          ],
        );
      case SlotType.elective:
        accent = CsColors.lilac;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.subjectName(e!), style: t.textTheme.titleSmall),
            Text('Room depends on your elective. Pick it under Me → Open electives.', style: t.textTheme.bodySmall),
          ],
        );
      case SlotType.scheduled:
      case SlotType.noTimetable:
        accent = CsColors.forSubject(e?.subjectCode);
        body = _EntryBody(data: data, entry: e!);
    }
    final card = Container(
      decoration: BoxDecoration(
        color: slot.type == SlotType.noEntry ? Colors.transparent : (t.cardTheme.color ?? t.colorScheme.surface),
        borderRadius: BorderRadius.circular(18),
        border: slot.type == SlotType.noEntry
            ? Border.all(color: t.colorScheme.outlineVariant)
            : (live ? Border.all(color: accent, width: 2) : null),
      ),
      padding: const EdgeInsets.all(Gap.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: time),
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: Gap.m),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
          ),
          Expanded(child: body),
          if (live) const Pill('Now', color: CsColors.coral),
        ],
      ),
    );
    if (e == null || slot.type == SlotType.noEntry) return card;
    return InkWell(borderRadius: BorderRadius.circular(18), onTap: () => _showEntry(context, data, e), child: card);
  }
}

class _EntryBody extends StatelessWidget {
  final CampusData data;
  final TimetableEntry entry;
  const _EntryBody({required this.data, required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = entry;
    final faculty = data.facultyName(e);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(data.subjectName(e), style: t.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (e.reviewFlags.isNotEmpty) const Icon(Icons.flag_rounded, size: 16, color: CsColors.partial),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            Pill(
              e.kind == EntryKind.lab ? 'Lab' : (e.kind == EntryKind.tutorial ? 'Tutorial' : 'Lecture'),
              color: CsColors.forSubject(e.subjectCode),
            ),
            Pill(
              e.roomId != null ? data.roomDisplay(e.roomId) : 'Room not listed',
              color: t.colorScheme.primary,
              icon: Icons.place_outlined,
            ),
            if (e.batch != null) Pill('Batch ${e.batch}', color: t.colorScheme.tertiary),
          ],
        ),
        if (faculty != null) ...[
          const SizedBox(height: 4),
          Text(faculty, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

void _showEntry(BuildContext context, CampusData data, TimetableEntry e) {
  final t = Theme.of(context);
  final room = data.roomsById[e.roomId];
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.subjectName(e), style: t.textTheme.titleLarge),
            const SizedBox(height: Gap.m),
            InfoRow(
              Icons.schedule_rounded,
              'Time',
              '${weekdayNames[e.weekday - 1]} ${formatHm12(e.startMin)} – ${formatHm12(e.endMin)} (${e.durationMin} min)',
            ),
            if (e.subjectCode != null) InfoRow(Icons.code_rounded, 'Code', e.subjectCode!),
            InfoRow(Icons.person_outline, 'Faculty', data.facultyName(e) ?? 'Not listed'),
            InfoRow(
              Icons.place_outlined,
              'Room',
              room == null
                  ? (e.roomLabel ?? 'Not listed')
                  : '${room.name} · ${data.floors.where((f) => f.id == room.floorId).firstOrNull?.name ?? ''}',
            ),
            if (e.batch != null) InfoRow(Icons.groups_outlined, 'Batch', e.batch!),
            if (e.sharedNote != null) InfoRow(Icons.merge_type_rounded, 'Shared', e.sharedNote!),
            if (e.reviewFlags.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: Gap.m),
                padding: const EdgeInsets.all(Gap.m),
                decoration: BoxDecoration(color: CsColors.partial.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text('Flagged for review: ${e.reviewFlags.join(' ')}', style: t.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    ),
  );
}

class _WeekView extends StatelessWidget {
  final CampusData data;
  final ScheduleService svc;
  final ScheduleProfile profile;
  final DateTime monday;
  const _WeekView({required this.data, required this.svc, required this.profile, required this.monday});

  static const hourH = 64.0, dayW = 118.0, gutter = 44.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final st = data.settings;
    final hours = (st.dayEndMin - st.dayStartMin) / 60;
    final days = [for (var i = 0; i < 6; i++) monday.add(Duration(days: i))];
    final anyTimetable = days.any((d) => svc.hasTimetable(profile, d));
    if (!anyTimetable) {
      return const EmptyState(
        icon: Icons.event_busy_rounded,
        title: 'No published timetable this week',
        message: 'This week is outside the effective period of your group\'s timetable.',
      );
    }
    double y(int m) => (m - st.dayStartMin) / 60 * hourH;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: gutter),
                for (final d in days)
                  SizedBox(
                    width: dayW,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.s),
                      child: Text('${weekdayShort[d.weekday - 1]} ${d.day}', textAlign: TextAlign.center, style: t.textTheme.labelLarge),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: hours * hourH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: gutter,
                    child: Stack(
                      children: [
                        for (var m = st.dayStartMin; m < st.dayEndMin; m += 60)
                          Positioned(
                            top: y(m),
                            child: Text(formatHm(m), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    Container(
                      width: dayW,
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.5))),
                      ),
                      child: Stack(
                        children: [
                          for (var m = st.dayStartMin; m < st.dayEndMin; m += 60)
                            Positioned(
                              top: y(m),
                              left: 0,
                              right: 0,
                              child: Divider(height: 1, color: t.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                          if (!svc.hasTimetable(profile, d))
                            Positioned.fill(
                              child: Center(child: Text('Not covered', style: t.textTheme.labelSmall)),
                            )
                          else
                            ..._blocks(context, svc.entriesOn(profile, d), y),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _blocks(BuildContext context, List<TimetableEntry> entries, double Function(int) y) {
    final t = Theme.of(context);
    final out = <Widget>[];
    for (final e in entries) {
      // Parallel batch sessions share the column width.
      final parallel = entries.where((o) => o.overlaps(e.startMin, e.endMin)).toList();
      final idx = parallel.indexOf(e);
      final width = (dayW - 6) / parallel.length;
      final color = e.kind.isFreePeriod
          ? CsColors.mint
          : (e.kind == EntryKind.elective ? CsColors.lilac : CsColors.forSubject(e.subjectCode));
      out.add(
        Positioned(
          top: y(e.startMin) + 2,
          left: 3 + idx * width,
          width: width - 2,
          height: (e.endMin - e.startMin) / 60 * hourH - 4,
          child: InkWell(
            onTap: () => _showEntry(context, data, e),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: e.kind.isFreePeriod ? 0.12 : 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                e.kind.isFreePeriod
                    ? (e.kind == EntryKind.library ? 'Library' : 'Break')
                    : '${e.subjectCode ?? ''}${e.batch != null ? ' ${e.batch}' : ''}\n${e.roomId != null ? data.roomDisplay(e.roomId) : ''}',
                overflow: TextOverflow.fade,
                style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }
}
