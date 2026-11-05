import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/campus_data.dart';
import '../../domain/availability.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

// Shared by the Rooms explorer and the Academic Block interior so both show
// the same verified floor plans and the same timetable-based room status.

class FloorLegend extends StatelessWidget {
  const FloorLegend({super.key});
  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String l) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(l, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.l, vertical: Gap.s),
      child: Wrap(
        spacing: Gap.m,
        runSpacing: 4,
        children: [
          item(CsColors.occupied, 'Occupied'),
          item(CsColors.partial, 'No class listed (unverified)'),
          item(CsColors.free, 'Free (verified)'),
          item(CsColors.unavailable, 'Not a classroom'),
        ],
      ),
    );
  }
}

class FloorPlanView extends StatelessWidget {
  final FloorLayout floor;
  final Map<String, RoomAvailability> results;
  final ValueChanged<RoomAvailability> onTap;

  /// Room shown as selected (thicker outline), e.g. where the character went.
  final String? highlightRoomId;
  const FloorPlanView({super.key, required this.floor, required this.results, required this.onTap, this.highlightRoomId});

  static IconData? _icon(String kind) => switch (kind) {
    'washroom' => Icons.wc_rounded,
    'exit' => Icons.directions_run_rounded,
    'lift' => Icons.elevator_rounded,
    'stairs' => Icons.stairs_rounded,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        return Stack(
          children: [
            Positioned(
              left: w * 0.33,
              top: h * 0.414,
              width: w * 0.333,
              height: h * 0.17,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      floor.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ),
            for (final r in floor.regions)
              Positioned(
                left: r.x * w,
                top: r.y * h,
                width: r.w * w,
                height: r.h * h,
                child: _RegionTile(
                  region: r,
                  result: r.roomId != null ? results[r.roomId] : null,
                  onTap: onTap,
                  icon: _icon(r.kind),
                  selected: r.roomId != null && r.roomId == highlightRoomId,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RegionTile extends StatelessWidget {
  final FloorRegion region;
  final RoomAvailability? result;
  final ValueChanged<RoomAvailability> onTap;
  final IconData? icon;
  final bool selected;
  const _RegionTile({required this.region, required this.result, required this.onTap, this.icon, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final res = result;
    final bookable = res != null && res.room?.bookable == true;
    final color = bookable ? CsColors.forStatus(res.status) : t.colorScheme.outlineVariant;
    final label = region.label.replaceAll(' (unlabelled in source)', '');
    final tile = Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: bookable ? color.withValues(alpha: 0.18) : t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(
          color: selected ? t.colorScheme.primary : (bookable ? color : t.colorScheme.outlineVariant),
          width: selected ? 3 : (bookable ? 1.5 : 1),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(icon, color: t.colorScheme.onSurfaceVariant),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: bookable ? FontWeight.w700 : FontWeight.w500, color: t.colorScheme.onSurface),
                ),
              ),
            ),
    );
    if (res == null) return Semantics(label: label, child: tile);
    return Semantics(
      button: true,
      label: '$label, ${CsColors.statusLabel(res.status)}',
      child: GestureDetector(onTap: () => onTap(res), child: tile),
    );
  }
}

class RoomDetailsSheet extends StatelessWidget {
  final CampusData data;
  final RoomAvailability r;
  final DateTime date;
  final int start, end;
  final ScrollController controller;
  const RoomDetailsSheet({
    super.key,
    required this.data,
    required this.r,
    required this.date,
    required this.start,
    required this.end,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final room = r.room;
    final floor = data.floors.where((f) => f.id == room?.floorId).firstOrNull;
    final color = CsColors.forStatus(r.status);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
      children: [
        Text(room?.name ?? r.roomId, style: t.textTheme.headlineSmall),
        Text(
          '${floor?.name ?? ''} · ${room?.type ?? ''}${room?.capacity != null ? ' · ${room!.capacity} seats' : ''}',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.l),
        Container(
          padding: const EdgeInsets.all(Gap.m),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 12, color: color),
                  const SizedBox(width: Gap.s),
                  Expanded(
                    child: Text(CsColors.statusLabel(r.status), style: t.textTheme.titleSmall?.copyWith(color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${DateFormat('EEE d MMM').format(date)}, ${formatHm12(start)} – ${formatHm12(end)}', style: t.textTheme.bodySmall),
              const SizedBox(height: Gap.s),
              Text(r.reason, style: t.textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: Gap.s),
        Text(
          'Based on published timetables only, not on whether the room is physically open or empty.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
        ),
        if (r.nextUse != null) ...[
          const SizedBox(height: Gap.l),
          InfoRow(
            Icons.update_rounded,
            'Next class',
            '${data.subjectName(r.nextUse!.entry)} at ${formatHm12(r.nextUse!.entry.startMin)} (${r.nextUse!.group.label})',
          ),
        ],
        const SizedBox(height: Gap.l),
        Text('Scheduled use on ${DateFormat('EEEE').format(date)}', style: t.textTheme.titleMedium),
        const SizedBox(height: Gap.s),
        if (r.dayUses.isEmpty)
          Text('No classes in the published timetables for this day.', style: t.textTheme.bodyMedium)
        else
          for (final u in r.dayUses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: CsColors.forSubject(u.entry.subjectCode).withValues(alpha: 0.2),
                child: Text(
                  u.entry.subjectCode?.replaceAll('OE-', 'OE') ?? '?',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              title: Text(data.subjectName(u.entry)),
              subtitle: Text(
                '${formatHm12(u.entry.startMin)} – ${formatHm12(u.entry.endMin)} · ${u.group.label}${u.entry.batch != null ? ' · ${u.entry.batch}' : ''}',
              ),
            ),
        const SizedBox(height: Gap.m),
        Text('Gaps between published classes', style: t.textTheme.titleMedium),
        const SizedBox(height: Gap.s),
        Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [for (final f in r.freeIntervals) Pill('${formatHm12(f.startMin)} – ${formatHm12(f.endMin)}', color: CsColors.partial)],
        ),
        const SizedBox(height: Gap.l),
        Text(r.coverage.describe(), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
