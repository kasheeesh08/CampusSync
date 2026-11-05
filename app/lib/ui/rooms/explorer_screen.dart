import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/campus_data.dart';
import '../../domain/availability.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'floor_plan.dart';

class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});
  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  String _floorId = '4';
  late DateTime _date;
  late int _start;
  int _duration = 60;
  final _search = TextEditingController();
  String _query = '';
  final _viewer = TransformationController();

  @override
  void initState() {
    super.initState();
    _setNow();
  }

  void _setNow() {
    final now = DateTime.now();
    _date = dateOnly(now);
    final m = now.hour * 60 + now.minute;
    _start = (m.clamp(8 * 60, 17 * 60) ~/ 60) * 60;
  }

  @override
  void dispose() {
    _search.dispose();
    _viewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final data = s.data;
    if (data == null) {
      return const SafeArea(
        child: EmptyState(icon: Icons.meeting_room_outlined, title: 'No room data', message: 'Pull to refresh on the Campus tab.'),
      );
    }
    final st = data.settings;
    final end = (_start + _duration).clamp(st.dayStartMin + 1, st.dayEndMin);
    final results = {for (final r in data.availability.checkAll(_date, _start, end)) r.roomId: r};
    final floor = data.floors.firstWhere((f) => f.id == _floorId, orElse: () => data.floors.first);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, Gap.s),
            child: Row(
              children: [
                Expanded(child: Text('Classrooms', style: t.textTheme.headlineSmall)),
                IconButton(
                  tooltip: 'How availability works',
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: () => _explain(context, data),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.l),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search rooms and labs, e.g. CR 402 or AI Lab',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
          const SizedBox(height: Gap.s),
          _TimeBar(
            date: _date,
            start: _start,
            duration: _duration,
            dayStart: st.dayStartMin,
            dayEnd: st.dayEndMin,
            onDate: (d) => setState(() => _date = d),
            onStart: (m) => setState(() => _start = m),
            onDuration: (d) => setState(() => _duration = d),
            onNow: () => setState(_setNow),
          ),
          if (_query.isNotEmpty)
            Expanded(
              child: _SearchResults(data: data, results: results, query: _query, onOpen: (r) => _openRoom(context, data, results[r.id]!)),
            )
          else ...[
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Gap.l),
                children: [
                  for (final f in data.floors)
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.s),
                      child: ChoiceChip(
                        label: Text(f.shortLabel),
                        tooltip: f.name,
                        selected: f.id == _floorId,
                        onSelected: (_) => setState(() {
                          _floorId = f.id;
                          _viewer.value = Matrix4.identity();
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.l, Gap.xs, Gap.l, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${floor.name}${floor.note != null ? ' · ${floor.note}' : ''}',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            const FloorLegend(),
            Expanded(
              child: floor.missingLayout
                  ? EmptyState(
                      icon: Icons.layers_clear_rounded,
                      title: 'Layout not available',
                      message: floor.note ?? 'No layout was supplied for this floor.',
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.m),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ColoredBox(
                          color: t.cardTheme.color ?? Colors.white,
                          child: InteractiveViewer(
                            transformationController: _viewer,
                            minScale: 1,
                            maxScale: 4,
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: floor.aspectRatio,
                                child: FloorPlanView(floor: floor, results: results, onTap: (r) => _openRoom(context, data, r)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  void _openRoom(BuildContext context, CampusData data, RoomAvailability r) {
    final room = r.room;
    final floor = data.floors.where((f) => f.id == room?.floorId).firstOrNull;
    if (floor != null && _floorId != floor.id) setState(() => _floorId = floor.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (c, scroll) => RoomDetailsSheet(data: data, r: r, date: _date, start: _start, end: _start + _duration, controller: scroll),
      ),
    );
  }

  void _explain(BuildContext context, CampusData data) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('About room availability'),
        content: SingleChildScrollView(
          child: Text(
            'Status is calculated from published timetables only.\n\n'
            '• Occupied: a published class overlaps the selected time.\n'
            '• No class listed · unverified: none of the published timetables use the room, but timetables for other '
            'departments and years are not uploaded yet, so the room may still be in use.\n'
            '• Free (verified schedule): all registered groups are published and the administrator has declared coverage complete.\n\n'
            'Scheduled availability is not the same as physical availability: rooms can be locked, booked ad hoc or under maintenance.\n\n'
            '${data.settings.coverageNote ?? ''}',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Got it'))],
      ),
    );
  }
}

class _TimeBar extends StatelessWidget {
  final DateTime date;
  final int start, duration, dayStart, dayEnd;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<int> onStart, onDuration;
  final VoidCallback onNow;
  const _TimeBar({
    required this.date,
    required this.start,
    required this.duration,
    required this.dayStart,
    required this.dayEnd,
    required this.onDate,
    required this.onStart,
    required this.onDuration,
    required this.onNow,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.l),
        children: [
          ActionChip(
            avatar: const Icon(Icons.event_rounded, size: 18),
            label: Text(DateFormat('EEE d MMM').format(date)),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2026, 7, 1),
                lastDate: DateTime(2027, 7, 31),
              );
              if (d != null) onDate(d);
            },
          ),
          const SizedBox(width: Gap.s),
          PopupMenuButton<int>(
            tooltip: 'Start time',
            onSelected: onStart,
            itemBuilder: (_) => [for (var m = dayStart; m < dayEnd; m += 60) PopupMenuItem(value: m, child: Text(formatHm12(m)))],
            child: Chip(
              avatar: const Icon(Icons.schedule_rounded, size: 18),
              label: Text('${formatHm12(start)} – ${formatHm12((start + duration).clamp(0, dayEnd))}'),
            ),
          ),
          const SizedBox(width: Gap.s),
          ChoiceChip(label: const Text('1 h'), selected: duration == 60, onSelected: (_) => onDuration(60)),
          const SizedBox(width: Gap.xs),
          ChoiceChip(label: const Text('2 h'), selected: duration == 120, onSelected: (_) => onDuration(120)),
          const SizedBox(width: Gap.s),
          ActionChip(avatar: const Icon(Icons.my_location_rounded, size: 18), label: const Text('Now'), onPressed: onNow),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final CampusData data;
  final Map<String, RoomAvailability> results;
  final String query;
  final ValueChanged<Room> onOpen;
  const _SearchResults({required this.data, required this.results, required this.query, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final rooms = data.rooms.where((r) => r.matches(query)).toList()..sort((a, b) => a.name.compareTo(b.name));
    if (rooms.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No rooms found',
        message: 'Nothing matches "$query". Try a code like CR 402.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Gap.l),
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: Gap.s),
      itemBuilder: (c, i) {
        final room = rooms[i];
        final r = results[room.id];
        final floor = data.floors.where((f) => f.id == room.floorId).firstOrNull;
        return SectionCard(
          onTap: r == null ? null : () => onOpen(room),
          child: Row(
            children: [
              Icon(room.type == 'lab' ? Icons.computer_rounded : Icons.meeting_room_rounded, color: Theme.of(c).colorScheme.primary),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.name, style: Theme.of(c).textTheme.titleSmall),
                    Text(floor?.name ?? '', style: Theme.of(c).textTheme.bodySmall),
                  ],
                ),
              ),
              if (r != null && room.bookable) Pill(CsColors.statusLabel(r.status).split(' ·').first, color: CsColors.forStatus(r.status)),
            ],
          ),
        );
      },
    );
  }
}
