import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/campus_data.dart';
import '../../domain/models.dart';
import '../../domain/validators.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_shell.dart';

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

// --------------------------------------------------------- academic groups --
class AdminGroups extends StatelessWidget {
  const AdminGroups({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    Widget namedList(String kind, String title, List<NamedEntity> items, {List<NamedEntity> parents = const []}) => SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: t.textTheme.titleMedium)),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _editNamed(context, kind, null, parents),
              ),
            ],
          ),
          for (final e in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.name, style: e.active ? null : const TextStyle(decoration: TextDecoration.lineThrough)),
              subtitle: Text(e.id),
              trailing: IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editNamed(context, kind, e, parents),
              ),
            ),
        ],
      ),
    );
    return AdminPage(
      title: 'Academic groups',
      subtitle:
          'Add departments, programmes, years and divisions without an app update. Students only see groups with published timetables.',
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('New group'),
          onPressed: () => _editGroup(context, d, null),
        ),
      ],
      child: ListView(
        children: [
          for (final g in d.groups)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.s),
              child: SectionCard(
                child: Row(
                  children: [
                    Icon(
                      g.isDivision ? Icons.groups_rounded : Icons.auto_awesome_rounded,
                      color: g.active ? t.colorScheme.primary : CsColors.unavailable,
                    ),
                    const SizedBox(width: Gap.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.label, style: t.textTheme.titleSmall),
                          Text(
                            '${g.id} · sem ${g.semester}${g.batches.isNotEmpty ? ' · batches ${g.batches.join(', ')}' : ''}'
                            ' · ${d.availability.effectiveVersion(g.id, DateTime.now()) != null ? 'timetable live today' : 'no live timetable today'}',
                            style: t.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!g.active) const Pill('inactive', color: CsColors.unavailable),
                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _editGroup(context, d, g)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Gap.l),
          Wrap(
            spacing: Gap.m,
            runSpacing: Gap.m,
            children: [
              SizedBox(width: 380, child: namedList('departments', 'Departments', d.departments)),
              SizedBox(width: 380, child: namedList('programs', 'Programmes', d.programs, parents: d.departments)),
              SizedBox(width: 380, child: namedList('academicYears', 'Academic years', d.academicYears)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editNamed(BuildContext context, String kind, NamedEntity? e, List<NamedEntity> parents) async {
    final s = context.read<AppState>();
    final name = TextEditingController(text: e?.name);
    String? parent = e?.parentId ?? parents.firstOrNull?.id;
    var active = e?.active ?? true;
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(e == null ? 'Add' : 'Edit'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) => Validators.required(v, 'Name'),
                ),
                if (parents.isNotEmpty) ...[
                  const SizedBox(height: Gap.m),
                  DropdownButtonFormField<String>(
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    initialValue: parent,
                    decoration: const InputDecoration(labelText: 'Belongs to'),
                    items: [for (final p in parents) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    onChanged: (v) => setD(() => parent = v),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setD(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(c, true) : null, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final entity = NamedEntity(
        id: e?.id ?? '${kind.substring(0, 3)}-${_slug(name.text)}',
        name: name.text.trim(),
        parentId: parent,
        active: active,
      );
      await adminAction(context, () => s.repo.saveNamedEntity(kind, entity, s.actor), success: 'Saved.');
    }
    name.dispose();
  }

  Future<void> _editGroup(BuildContext context, CampusData d, AcademicGroup? g) async {
    final s = context.read<AppState>();
    final result = await showDialog<AcademicGroup>(
      context: context,
      builder: (_) => _GroupDialog(data: d, group: g),
    );
    if (result == null || !context.mounted) return;
    if (g == null && d.groupsById.containsKey(result.id)) {
      showMessage(context, 'A group with id ${result.id} already exists.', error: true);
      return;
    }
    if (g != null && g.active && !result.active) {
      final ok = await confirmAction(
        context,
        title: 'Deactivate ${g.label}?',
        message: 'Its timetable will stop counting in room availability and students in this group will see no timetable.',
        confirm: 'Deactivate',
        destructive: true,
      );
      if (!ok || !context.mounted) return;
    }
    await adminAction(context, () => s.repo.saveGroup(result, s.actor), success: 'Group saved.');
  }
}

class _GroupDialog extends StatefulWidget {
  final CampusData data;
  final AcademicGroup? group;
  const _GroupDialog({required this.data, this.group});
  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final _form = GlobalKey<FormState>();
  late String _type = widget.group?.type ?? 'division';
  late String? _program = widget.group?.programId ?? widget.data.programs.firstOrNull?.id;
  late String? _year = widget.group?.academicYearId ?? widget.data.academicYears.firstOrNull?.id;
  late final _yos = TextEditingController(text: '${widget.group?.yearOfStudy ?? 3}');
  late final _sem = TextEditingController(text: '${widget.group?.semester ?? 5}');
  late final _div = TextEditingController(text: widget.group?.division ?? '');
  late final _label = TextEditingController(text: widget.group?.label ?? '');
  late final _batches = TextEditingController(text: widget.group?.batches.join(', ') ?? '');
  late bool _active = widget.group?.active ?? true;

  @override
  void dispose() {
    for (final c in [_yos, _sem, _div, _label, _batches]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _int(String? v, int min, int max, String f) {
    final n = int.tryParse(v ?? '');
    return n == null || n < min || n > max ? '$f must be $min–$max' : null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final editing = widget.group != null;
    return AlertDialog(
      title: Text(editing ? 'Edit group' : 'New academic group'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'division', child: Text('Division')),
                    DropdownMenuItem(value: 'electivePool', child: Text('Elective pool')),
                  ],
                  onChanged: editing ? null : (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: Gap.m),
                if (_type == 'division')
                  DropdownButtonFormField<String>(
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    initialValue: _program,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Programme'),
                    items: [for (final p in d.programs) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    onChanged: editing ? null : (v) => setState(() => _program = v),
                    validator: (v) => v == null ? 'Select a programme' : null,
                  ),
                const SizedBox(height: Gap.m),
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _year,
                  decoration: const InputDecoration(labelText: 'Academic year'),
                  items: [for (final y in d.academicYears) DropdownMenuItem(value: y.id, child: Text(y.name))],
                  onChanged: editing ? null : (v) => setState(() => _year = v),
                  validator: (v) => v == null ? 'Select a year' : null,
                ),
                const SizedBox(height: Gap.m),
                Row(
                  children: [
                    if (_type == 'division') ...[
                      Expanded(
                        child: TextFormField(
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          controller: _yos,
                          enabled: !editing,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Year of study'),
                          validator: (v) => _int(v, 1, 6, 'Year'),
                        ),
                      ),
                      const SizedBox(width: Gap.s),
                    ],
                    Expanded(
                      child: TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        controller: _sem,
                        enabled: !editing,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Semester'),
                        validator: (v) => _int(v, 1, 12, 'Semester'),
                      ),
                    ),
                    if (_type == 'division') ...[
                      const SizedBox(width: Gap.s),
                      Expanded(
                        child: TextFormField(
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          controller: _div,
                          enabled: !editing,
                          maxLength: 2,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Division', hintText: 'e.g. A', counterText: ''),
                          validator: (v) => RegExp(r'^[A-Za-z]{1,2}$').hasMatch(v?.trim() ?? '') ? null : 'Letters only',
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Gap.m),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'Display label *', hintText: 'e.g. B.Tech Computer · Sem V · Div A'),
                  validator: Validators.title,
                ),
                const SizedBox(height: Gap.m),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _batches,
                  decoration: const InputDecoration(labelText: 'Lab batches (comma separated)', hintText: 'e.g. A1, A2'),
                  validator: (v) =>
                      (v ?? '')
                          .split(',')
                          .map((x) => x.trim())
                          .where((x) => x.isNotEmpty)
                          .every((x) => RegExp(r'^[A-Za-z0-9]{1,4}$').hasMatch(x))
                      ? null
                      : 'Use short codes like A1, A2',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final g = widget.group;
            final program = d.programs.where((p) => p.id == _program).firstOrNull;
            final batches = _batches.text.split(',').map((x) => x.trim().toUpperCase()).where((x) => x.isNotEmpty).toList();
            final sem = int.parse(_sem.text);
            final div = _div.text.trim().toUpperCase();
            Navigator.pop(
              context,
              g != null
                  ? g.copyWith(label: _label.text.trim(), active: _active, batches: batches)
                  : AcademicGroup(
                      id: _type == 'division'
                          ? '${_slug(program?.name ?? 'group')}-$_year-sem$sem-div-${div.toLowerCase()}'
                          : 'pool-${_slug(_label.text)}-$_year',
                      type: _type,
                      programId: _type == 'division' ? _program : null,
                      departmentId: _type == 'division' ? program?.parentId : null,
                      academicYearId: _year!,
                      yearOfStudy: _type == 'division' ? int.parse(_yos.text) : null,
                      semester: sem,
                      division: _type == 'division' ? div : null,
                      label: _label.text.trim(),
                      active: _active,
                      batches: batches,
                    ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ rooms --
class AdminRooms extends StatefulWidget {
  const AdminRooms({super.key});
  @override
  State<AdminRooms> createState() => _AdminRoomsState();
}

class _AdminRoomsState extends State<AdminRooms> {
  String _q = '';
  String _floor = 'all';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final rooms = d.rooms.where((r) => r.matches(_q) && (_floor == 'all' || r.floorId == _floor)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return AdminPage(
      title: 'Rooms & floors',
      subtitle: 'Physical rooms are separate from timetable assignments. Inactive rooms are never shown as available.',
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.map_outlined),
          label: const Text('Floor region mapping'),
          onPressed: () => _floorMapping(context, d),
        ),
        FilledButton.icon(icon: const Icon(Icons.add_rounded), label: const Text('New room'), onPressed: () => _editRoom(context, d, null)),
      ],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Search rooms', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const SizedBox(width: Gap.m),
              DropdownButton<String>(
                value: _floor,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All floors')),
                  for (final f in d.floors) DropdownMenuItem(value: f.id, child: Text(f.name)),
                ],
                onChanged: (v) => setState(() => _floor = v!),
              ),
            ],
          ),
          const SizedBox(height: Gap.m),
          Expanded(
            child: Card(
              child: ListView.separated(
                itemCount: rooms.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final r = rooms[i];
                  return ListTile(
                    leading: Icon(
                      r.type == 'lab' ? Icons.computer_rounded : Icons.meeting_room_rounded,
                      color: r.active ? t.colorScheme.primary : CsColors.unavailable,
                    ),
                    title: Text(r.name),
                    subtitle: Text(
                      '${r.id} · floor ${r.floorId} · ${r.type}${r.capacity != null ? ' · ${r.capacity} seats' : ''}'
                      '${r.bookable ? '' : ' · not schedulable'}${r.restrictionNote != null ? ' · ${r.restrictionNote}' : ''}',
                    ),
                    trailing: Wrap(
                      spacing: Gap.s,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!r.active) const Pill('inactive', color: CsColors.unavailable),
                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _editRoom(context, d, r)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editRoom(BuildContext context, CampusData d, Room? r) async {
    final s = context.read<AppState>();
    final form = GlobalKey<FormState>();
    final code = TextEditingController(text: r?.code);
    final name = TextEditingController(text: r?.name);
    final cap = TextEditingController(text: r?.capacity?.toString());
    final note = TextEditingController(text: r?.restrictionNote);
    var type = r?.type ?? 'classroom';
    var floor = r?.floorId ?? d.floors.firstWhere((f) => !f.missingLayout).id;
    var active = r?.active ?? true;
    var bookable = r?.bookable ?? true;
    final result = await showDialog<Room>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(r == null ? 'New room' : 'Edit ${r.name}'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      controller: code,
                      enabled: r == null,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Room code *', hintText: 'e.g. CR-210'),
                      validator: (v) {
                        final x = v?.trim().toUpperCase() ?? '';
                        if (!RegExp(r'^[A-Z0-9\-]{2,40}$').hasMatch(x)) return 'Use letters, digits and hyphens';
                        if (r == null && d.roomsById.containsKey(x)) return 'Room already exists';
                        return null;
                      },
                    ),
                    const SizedBox(height: Gap.m),
                    TextFormField(
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Display name *', hintText: 'e.g. CR 210'),
                      validator: (v) => Validators.required(v, 'Name'),
                    ),
                    const SizedBox(height: Gap.m),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            initialValue: type,
                            decoration: const InputDecoration(labelText: 'Type'),
                            items: const [
                              DropdownMenuItem(value: 'classroom', child: Text('Classroom')),
                              DropdownMenuItem(value: 'lab', child: Text('Lab')),
                              DropdownMenuItem(value: 'tutorial', child: Text('Tutorial room')),
                              DropdownMenuItem(value: 'facility', child: Text('Facility')),
                            ],
                            onChanged: (v) => setD(() => type = v!),
                          ),
                        ),
                        const SizedBox(width: Gap.s),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            initialValue: floor,
                            decoration: const InputDecoration(labelText: 'Floor'),
                            items: [for (final f in d.floors) DropdownMenuItem(value: f.id, child: Text(f.name))],
                            onChanged: r == null ? (v) => setD(() => floor = v!) : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.m),
                    TextFormField(
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      controller: cap,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Capacity (if known)', hintText: 'Leave blank if unknown'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) || ((int.tryParse(v) ?? 0) > 0 && int.parse(v) <= 1000) ? null : 'Enter 1–1000',
                    ),
                    const SizedBox(height: Gap.m),
                    TextFormField(
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      controller: note,
                      decoration: const InputDecoration(labelText: 'Restriction note', hintText: 'e.g. Under maintenance until 30 Oct'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: (v) => setD(() => active = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Used for scheduled classes'),
                      value: bookable,
                      onChanged: (v) => setD(() => bookable = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final id = r?.id ?? code.text.trim().toUpperCase();
                Navigator.pop(
                  c,
                  Room(
                    id: id,
                    code: r?.code ?? id,
                    name: name.text.trim(),
                    type: type,
                    floorId: floor,
                    capacity: int.tryParse(cap.text.trim()),
                    active: active,
                    bookable: bookable,
                    aliases: r?.aliases ?? const [],
                    restrictionNote: note.text.trim().isEmpty ? null : note.text.trim(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    for (final x in [code, name, cap, note]) {
      x.dispose();
    }
    if (result != null && context.mounted) {
      await adminAction(context, () => s.repo.saveRoom(result, s.actor), success: 'Room saved.');
    }
  }

  void _floorMapping(BuildContext context, CampusData d) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(value: context.read<AppState>(), child: const _FloorMappingPage()),
    ),
  );
}

class _FloorMappingPage extends StatefulWidget {
  const _FloorMappingPage();
  @override
  State<_FloorMappingPage> createState() => _FloorMappingPageState();
}

class _FloorMappingPageState extends State<_FloorMappingPage> {
  String _floor = '4';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final floor = d.floors.firstWhere((f) => f.id == _floor, orElse: () => d.floors.first);
    return Scaffold(
      appBar: AppBar(title: const Text('Floor region mapping')),
      body: Padding(
        padding: const EdgeInsets.all(Gap.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Gap.s,
              children: [
                for (final f in d.floors)
                  ChoiceChip(label: Text(f.shortLabel), selected: f.id == _floor, onSelected: (_) => setState(() => _floor = f.id)),
              ],
            ),
            const SizedBox(height: Gap.s),
            Text(
              'Tap a region to link it to a room record. Region shapes come from the supplied floor-plan images.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: Gap.m),
            Expanded(
              child: floor.missingLayout
                  ? EmptyState(icon: Icons.layers_clear, title: 'No layout', message: floor.note ?? '')
                  : Center(
                      child: AspectRatio(
                        aspectRatio: floor.aspectRatio,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            return Stack(
                              children: [
                                for (final r in floor.regions)
                                  Positioned(
                                    left: r.x * c.maxWidth,
                                    top: r.y * c.maxHeight,
                                    width: r.w * c.maxWidth,
                                    height: r.h * c.maxHeight,
                                    child: InkWell(
                                      onTap: () => _map(context, d, floor, r),
                                      child: Container(
                                        margin: const EdgeInsets.all(1),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: (r.roomId != null ? CsColors.seed : CsColors.unavailable).withValues(alpha: 0.15),
                                          border: Border.all(color: r.roomId != null ? CsColors.seed : t.colorScheme.outlineVariant),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: FittedBox(
                                          child: Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: Text('${r.label}\n${r.roomId ?? '—'}', textAlign: TextAlign.center),
                                          ),
                                        ),
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
          ],
        ),
      ),
    );
  }

  Future<void> _map(BuildContext context, CampusData d, FloorLayout floor, FloorRegion region) async {
    final s = context.read<AppState>();
    final rooms = d.rooms.where((r) => r.floorId == floor.id).toList()..sort((a, b) => a.name.compareTo(b.name));
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Link "${region.label}"'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, ''), child: const Text('— No room (decorative / facility) —')),
          for (final r in rooms) SimpleDialogOption(onPressed: () => Navigator.pop(c, r.id), child: Text('${r.name} (${r.id})')),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final updated = FloorLayout(
      id: floor.id,
      name: floor.name,
      order: floor.order,
      note: floor.note,
      aspectRatio: floor.aspectRatio,
      missingLayout: floor.missingLayout,
      regions: [
        for (final r in floor.regions)
          r.id == region.id
              ? FloorRegion(id: r.id, label: r.label, kind: r.kind, roomId: choice.isEmpty ? null : choice, x: r.x, y: r.y, w: r.w, h: r.h)
              : r,
      ],
    );
    await adminAction(context, () => s.repo.saveFloor(updated, s.actor), success: 'Region mapping saved.');
  }
}

// --------------------------------------------------------------- settings --
class AdminSettings extends StatelessWidget {
  const AdminSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final st = d.settings;
    final t = Theme.of(context);
    return AdminPage(
      title: 'Campus settings',
      child: ListView(
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Timetable coverage declared complete'),
                  subtitle: const Text(
                    'Turn on only when every department and year that uses these rooms has a published timetable. '
                    'Until then, students see "no class listed · unverified" instead of "free".',
                  ),
                  value: st.coverageDeclaredComplete,
                  onChanged: (v) async {
                    final ok = await confirmAction(
                      context,
                      title: v ? 'Declare coverage complete?' : 'Mark coverage incomplete?',
                      message: v
                          ? 'Rooms without a published class will be shown to students as verified free. Confirm that all timetables using campus rooms are uploaded.'
                          : 'Rooms will be shown as unverified.',
                      confirm: 'Confirm',
                    );
                    if (ok && context.mounted) {
                      await adminAction(
                        context,
                        () => s.repo.saveSettings(
                          CampusSettings(
                            timezone: st.timezone,
                            dayStartMin: st.dayStartMin,
                            dayEndMin: st.dayEndMin,
                            coverageDeclaredComplete: v,
                            coverageNote: st.coverageNote,
                          ),
                          s.actor,
                        ),
                        success: 'Settings saved.',
                      );
                    }
                  },
                ),
                const Divider(),
                InfoRow(Icons.public, 'Timezone', st.timezone),
                InfoRow(Icons.schedule, 'Campus hours', '${formatHm(st.dayStartMin)} – ${formatHm(st.dayEndMin)}'),
                if (st.coverageNote != null) InfoRow(Icons.info_outline, 'Coverage note', st.coverageNote!),
              ],
            ),
          ),
          const SizedBox(height: Gap.m),
          Text(
            'Data shown to students is synchronised from Firestore; changes reach devices on their next refresh.',
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
