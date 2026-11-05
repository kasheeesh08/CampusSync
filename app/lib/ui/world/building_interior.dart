import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/campus_data.dart';
import '../../domain/availability.dart';
import '../../domain/focus.dart';
import '../../domain/models.dart';
import '../rooms/floor_plan.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'character.dart';
import 'library_study.dart';

/// Zoom-and-fade route used when the character enters a building.
Route<void> enterRoute(Widget page) => PageRouteBuilder<void>(
  transitionDuration: const Duration(milliseconds: 450),
  reverseTransitionDuration: const Duration(milliseconds: 300),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, a, _, child) {
    final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curved), child: child),
    );
  },
);

/// Interior of the main Academic Block: floors LG–8 drawn from the supplied
/// floor-plan images. The character rides the lift between floors and walks
/// to the room the student selects.
class BuildingInteriorScreen extends StatefulWidget {
  final String initialFloorId;
  const BuildingInteriorScreen({super.key, this.initialFloorId = 'G'});

  @override
  State<BuildingInteriorScreen> createState() => _BuildingInteriorScreenState();
}

class _BuildingInteriorScreenState extends State<BuildingInteriorScreen> {
  late String _floorId = widget.initialFloorId;
  String? _selectedRoomId;
  Offset? _target; // normalised character position on the plan
  bool _walking = false;

  /// The current campus hour (clamped to campus hours), like the Rooms tab.
  (DateTime, int, int) _interval(CampusData d) {
    final now = DateTime.now();
    final st = d.settings;
    final m = (now.hour * 60 + now.minute).clamp(st.dayStartMin, st.dayEndMin - 60);
    final start = (m ~/ 60) * 60;
    return (dateOnly(now), start, start + 60);
  }

  Offset _liftPosition(FloorLayout f) {
    final lift = f.regions.where((r) => r.kind == 'lift').firstOrNull;
    if (lift == null) return const Offset(0.5, 0.5);
    return Offset(lift.x + lift.w / 2, lift.y + lift.h + 0.05);
  }

  Future<void> _selectRoom(BuildContext context, CampusData d, FloorLayout floor, RoomAvailability r) async {
    final region = floor.regions.firstWhere((x) => x.roomId == r.roomId);
    setState(() {
      _selectedRoomId = r.roomId;
      _target = Offset(region.x + region.w / 2, region.y + region.h / 2);
      _walking = true;
    });
    final reduce = context.read<AppState>().prefs.reduceMotion;
    await Future<void>.delayed(Duration(milliseconds: reduce ? 50 : 650));
    if (!mounted) return;
    setState(() => _walking = false);
    if (!context.mounted) return;
    if (r.roomId == libraryStudySpace.roomId) return _showLibraryEntry(context);
    final (date, start, end) = _interval(d);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (c, scroll) => RoomDetailsSheet(data: d, r: r, date: date, start: start, end: end, controller: scroll),
      ),
    );
  }

  Future<void> _showLibraryEntry(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final t = Theme.of(c);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Library · Floor 7', style: t.textTheme.titleLarge),
              const SizedBox(height: Gap.s),
              Text(
                'The Library appears on the supplied Floor 7 plan. Inside, you can sit at a desk and run a focus session.',
                style: t.textTheme.bodyMedium,
              ),
              const SizedBox(height: Gap.l),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.menu_book_rounded),
                  label: const Text('Enter library'),
                  onPressed: () {
                    Navigator.pop(c);
                    Navigator.push(context, enterRoute(const LibraryStudyScreen()));
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final d = s.data;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Academic Block')),
        body: EmptyState(icon: Icons.cloud_off_rounded, title: 'No campus data', message: s.error ?? 'Pull to refresh on the Campus tab.'),
      );
    }
    final floors = d.floors;
    final floor = floors.firstWhere((f) => f.id == _floorId, orElse: () => floors.first);
    final (date, start, end) = _interval(d);
    final roomIds = [
      for (final r in floor.regions)
        if (r.roomId != null) r.roomId!,
    ];
    final results = {for (final r in d.availability.checkAll(date, start, end, roomIds: roomIds)) r.roomId: r};
    final pos = _target ?? _liftPosition(floor);
    final libraryHere = floor.regions.any((r) => r.roomId == libraryStudySpace.roomId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back to campus', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Academic Block'),
            Text(
              'Floor plans from the supplied MPSTME layouts',
              style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Lift panel: one button per floor.
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Gap.l),
                children: [
                  for (final f in floors)
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.s),
                      child: ChoiceChip(
                        avatar: f.regions.any((r) => r.roomId == libraryStudySpace.roomId)
                            ? const Icon(Icons.menu_book_rounded, size: 16)
                            : null,
                        label: Text(f.shortLabel),
                        tooltip: f.name,
                        selected: f.id == floor.id,
                        onSelected: (_) => setState(() {
                          _floorId = f.id;
                          _selectedRoomId = null;
                          _target = null; // character steps out of the lift
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
                      '${floor.name}${floor.note != null ? ' · ${floor.note}' : ''}\n'
                      'Room status for ${DateFormat('EEE d MMM').format(date)}, ${formatHm12(start)}–${formatHm12(end)} (published timetables). Tap a room.',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            if (libraryHere)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.l, Gap.s, Gap.l, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('Enter library'),
                    onPressed: () => Navigator.push(context, enterRoute(const LibraryStudyScreen())),
                  ),
                ),
              ),
            const FloorLegend(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.m),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ColoredBox(
                    color: t.cardTheme.color ?? Colors.white,
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: s.prefs.reduceMotion ? 1 : 350),
                      child: Center(
                        key: ValueKey(floor.id),
                        child: AspectRatio(
                          aspectRatio: floor.aspectRatio,
                          child: LayoutBuilder(
                            builder: (context, c) {
                              const charSize = 44.0;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: FloorPlanView(
                                      floor: floor,
                                      results: results,
                                      highlightRoomId: _selectedRoomId,
                                      onTap: (r) => _selectRoom(context, d, floor, r),
                                    ),
                                  ),
                                  AnimatedPositioned(
                                    duration: Duration(milliseconds: s.prefs.reduceMotion ? 1 : 600),
                                    curve: Curves.easeInOutCubic,
                                    left: pos.dx * c.maxWidth - charSize * 0.4,
                                    top: pos.dy * c.maxHeight - charSize * 0.85,
                                    child: IgnorePointer(
                                      child: CampusCharacter(
                                        avatar: s.profile?.avatar ?? 'fox',
                                        color: characterColors[s.prefs.characterColor % characterColors.length],
                                        pose: _walking ? CharacterPose.walking : CharacterPose.idle,
                                        size: charSize,
                                        reduceMotion: s.prefs.reduceMotion,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
