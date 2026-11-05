import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/campus_data.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../domain/timetable_import.dart';
import '../../domain/timetable_validator.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_shell.dart';

final _dateFmt = DateFormat('d MMM yyyy');

class AdminTimetables extends StatefulWidget {
  const AdminTimetables({super.key});
  @override
  State<AdminTimetables> createState() => _AdminTimetablesState();
}

class _AdminTimetablesState extends State<AdminTimetables> {
  String? _groupId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final groups = d.groups;
    final gid = _groupId ?? groups.firstOrNull?.id;
    final group = d.groupsById[gid];
    final versions = d.versions.where((v) => v.groupId == gid).toList()..sort((a, b) => b.version.compareTo(a.version));
    return AdminPage(
      title: 'Timetables',
      subtitle: 'Drafts are never visible to students. Publishing archives the previous overlapping version.',
      actions: [
        if (group != null)
          FilledButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('New version'),
            onPressed: () => _openEditor(context, d, group, null),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            initialValue: gid,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Academic group'),
            items: [
              for (final g in groups)
                DropdownMenuItem(
                  value: g.id,
                  child: Text('${g.label}${g.active ? '' : ' (inactive)'}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _groupId = v),
          ),
          const SizedBox(height: Gap.l),
          Expanded(
            child: versions.isEmpty
                ? const EmptyState(
                    icon: Icons.calendar_today_outlined,
                    title: 'No timetable versions',
                    message: 'Create a version by importing CSV/JSON or entering classes manually.',
                  )
                : ListView(
                    children: [
                      for (final v in versions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.s),
                          child: _VersionCard(version: v, group: group!),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

void _openEditor(BuildContext context, CampusData d, AcademicGroup group, TimetableVersion? base, {bool copy = false}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppState>(),
        child: TimetableEditor(group: group, base: base, copy: copy),
      ),
    ),
  );
}

class _VersionCard extends StatelessWidget {
  final TimetableVersion version;
  final AcademicGroup group;
  const _VersionCard({required this.version, required this.group});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final v = version;
    final color = switch (v.status) {
      VersionStatus.published => CsColors.mint,
      VersionStatus.draft => CsColors.partial,
      VersionStatus.archived => CsColors.unavailable,
    };
    return SectionCard(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: Gap.s,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Version ${v.version}', style: t.textTheme.titleMedium),
                  const SizedBox(width: Gap.s),
                  Pill(v.status.name, color: color),
                ],
              ),
              Text(
                'Effective ${_dateFmt.format(v.effectiveFrom)} – ${v.effectiveTo != null ? _dateFmt.format(v.effectiveTo!) : 'open-ended'} · ${v.entries.length} entries',
                style: t.textTheme.bodySmall,
              ),
              Text(
                [
                  if (v.source != null) 'Source: ${v.source}',
                  if (v.createdBy != null) 'Created by ${v.createdBy}',
                  if (v.publishedBy != null)
                    'Published by ${v.publishedBy}${v.publishedAt != null ? ' on ${_dateFmt.format(v.publishedAt!)}' : ''}',
                ].join(' · '),
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          Wrap(
            spacing: Gap.s,
            children: [
              if (v.status == VersionStatus.draft) ...[
                OutlinedButton(onPressed: () => _openEditor(context, d, group, v), child: const Text('Edit / publish')),
                TextButton(
                  onPressed: () async {
                    if (await confirmAction(
                      context,
                      title: 'Archive draft?',
                      message: 'The draft will be kept but hidden from editing lists.',
                      confirm: 'Archive',
                    )) {
                      if (context.mounted) await adminAction(context, () => s.repo.archiveVersion(v, s.actor), success: 'Draft archived.');
                    }
                  },
                  child: const Text('Archive'),
                ),
              ] else
                OutlinedButton(onPressed: () => _openEditor(context, d, group, v, copy: true), child: const Text('New revision from this')),
              if (v.status == VersionStatus.archived)
                FilledButton.tonal(
                  onPressed: () async {
                    final validator = TimetableValidator(
                      rooms: d.rooms,
                      subjectCodes: d.subjects.map((x) => x.code),
                      facultyIds: d.faculty.map((f) => f.id),
                      settings: d.settings,
                    );
                    final r = validator.validate(v, group: group);
                    if (!r.canPublish) {
                      showMessage(context, 'This version has ${r.errors.length} validation error(s) and cannot be restored.', error: true);
                      return;
                    }
                    final ok = await confirmAction(
                      context,
                      title: 'Roll back to version ${v.version}?',
                      message:
                          'Version ${v.version} becomes the published timetable and the current published version is archived. Students see the change on next sync.',
                      confirm: 'Roll back',
                    );
                    if (ok && context.mounted) {
                      await adminAction(
                        context,
                        () => s.repo.publishVersion(v, d.versions, s.actor),
                        success: 'Rolled back to version ${v.version}.',
                      );
                    }
                  },
                  child: const Text('Roll back to this'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class TimetableEditor extends StatefulWidget {
  final AcademicGroup group;
  final TimetableVersion? base;
  final bool copy;
  const TimetableEditor({super.key, required this.group, this.base, this.copy = false});
  @override
  State<TimetableEditor> createState() => _TimetableEditorState();
}

class _TimetableEditorState extends State<TimetableEditor> {
  late List<TimetableEntry> _entries;
  late DateTime _from;
  DateTime? _to;
  late String _id;
  late int _number;
  String? _source;
  bool _busy = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    final d = context.read<AppState>().data!;
    final b = widget.base;
    final editingDraft = b != null && !widget.copy;
    _number = editingDraft ? b.version : nextVersionNumber(widget.group.id, d.versions);
    _id = editingDraft ? b.id : '${widget.group.id}-v$_number';
    _entries = [...?b?.entries];
    _from = b?.effectiveFrom ?? dateOnly(DateTime.now());
    _to = b?.effectiveTo;
    _source = b?.source;
  }

  ValidationResult _validate(CampusData d) {
    final validator = TimetableValidator(
      rooms: d.rooms,
      subjectCodes: d.subjects.map((x) => x.code),
      facultyIds: d.faculty.map((f) => f.id),
      settings: d.settings,
    );
    return validator.validate(
      _draft(),
      group: widget.group,
      otherPublished: d.versions.where((v) => v.status == VersionStatus.published),
      groupsById: d.groupsById,
    );
  }

  TimetableVersion _draft() => TimetableVersion(
    id: _id,
    groupId: widget.group.id,
    version: _number,
    status: VersionStatus.draft,
    effectiveFrom: _from,
    effectiveTo: _to,
    source: _source,
    entries: _entries,
  );

  String _newId() => 'm${DateTime.now().millisecondsSinceEpoch}-${_seq++}';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final result = _validate(d);
    final sorted = [..._entries]
      ..sort((a, b) => a.weekday != b.weekday ? a.weekday.compareTo(b.weekday) : a.startMin.compareTo(b.startMin));
    final issuesById = <String, List<ValidationIssue>>{};
    for (final i in result.issues) {
      if (i.entryId != null) (issuesById[i.entryId!] ??= []).add(i);
    }
    final wide = MediaQuery.sizeOf(context).width > 1100;

    final table = Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Gap.m),
            child: Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add entry'),
                  onPressed: () => _editEntry(context, d, null),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Import CSV / JSON'),
                  onPressed: () => _import(context, d),
                ),
                if (_entries.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Clear all'),
                    onPressed: () async {
                      if (await confirmAction(
                        context,
                        title: 'Remove all entries?',
                        message: 'This only affects this draft.',
                        confirm: 'Remove',
                        destructive: true,
                      )) {
                        setState(() => _entries = []);
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _entries.isEmpty
                ? const EmptyState(
                    icon: Icons.table_rows_outlined,
                    title: 'No entries',
                    message: 'Add entries manually or import a CSV/JSON file.',
                  )
                : ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final e = sorted[i];
                      final issues = issuesById[e.id] ?? const [];
                      final hasError = issues.any((x) => x.level == IssueLevel.error);
                      return ListTile(
                        leading: Icon(
                          hasError ? Icons.error_outline : (issues.isNotEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                          color: hasError ? t.colorScheme.error : (issues.isNotEmpty ? CsColors.partial : CsColors.mint),
                        ),
                        title: Text(
                          '${weekdayShort[e.weekday - 1]} ${formatHm(e.startMin)}–${formatHm(e.endMin)} · ${e.kind.wire} · ${e.subjectName ?? e.subjectCode ?? ''}'
                          '${e.batch != null ? ' · ${e.batch}' : ''}${e.cancelled ? ' · CANCELLED' : ''}',
                          style: e.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                        ),
                        subtitle: Text(
                          [
                            if (e.roomId != null) d.roomDisplay(e.roomId),
                            if (d.facultyName(e) != null) d.facultyName(e)!,
                            ...issues.map((x) => x.message),
                          ].join(' · '),
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: e.cancelled ? 'Restore' : 'Mark cancelled',
                              icon: Icon(e.cancelled ? Icons.undo_rounded : Icons.event_busy_outlined),
                              onPressed: () => setState(
                                () => _entries = [for (final x in _entries) x.id == e.id ? x.copyWith(cancelled: !x.cancelled) : x],
                              ),
                            ),
                            IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _editEntry(context, d, e)),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => setState(() => _entries = _entries.where((x) => x.id != e.id).toList()),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    final side = Card(
      child: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          Text('Effective period', style: t.textTheme.titleMedium),
          const SizedBox(height: Gap.s),
          Wrap(
            spacing: Gap.s,
            runSpacing: Gap.s,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text('From ${_dateFmt.format(_from)}'),
                onPressed: () async {
                  final p = await showDatePicker(context: context, initialDate: _from, firstDate: DateTime(2025), lastDate: DateTime(2030));
                  if (p != null) setState(() => _from = p);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_busy_rounded),
                label: Text(_to == null ? 'No end date' : 'To ${_dateFmt.format(_to!)}'),
                onPressed: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: _to ?? _from,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                  );
                  if (p != null) setState(() => _to = p);
                },
              ),
              if (_to != null) TextButton(onPressed: () => setState(() => _to = null), child: const Text('Clear end')),
            ],
          ),
          const SizedBox(height: Gap.m),
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            key: ValueKey(_source),
            initialValue: _source,
            decoration: const InputDecoration(labelText: 'Source / provenance', hintText: 'e.g. Official PDF dated 10/07/2026'),
            onChanged: (v) => _source = v.trim().isEmpty ? null : v.trim(),
          ),
          const SizedBox(height: Gap.l),
          Row(
            children: [
              Text('Validation', style: t.textTheme.titleMedium),
              const Spacer(),
              Pill('${result.errors.length} errors', color: result.errors.isEmpty ? CsColors.mint : t.colorScheme.error),
              const SizedBox(width: Gap.xs),
              Pill('${result.warnings.length} warnings', color: CsColors.partial),
            ],
          ),
          const SizedBox(height: Gap.s),
          for (final i in result.issues.where((i) => i.entryId == null || i.level == IssueLevel.error).take(30))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                i.level == IssueLevel.error ? Icons.error_outline : Icons.warning_amber_rounded,
                color: i.level == IssueLevel.error ? t.colorScheme.error : CsColors.partial,
                size: 20,
              ),
              title: Text(i.message),
            ),
          if (result.warnings.isNotEmpty)
            Text('Entry-level warnings (room shared with other groups, review flags) are shown on each row.', style: t.textTheme.bodySmall),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.group.label} · v$_number'),
        actions: [
          TextButton(onPressed: _busy ? null : () => _save(context, s, publish: false), child: const Text('Save draft')),
          const SizedBox(width: Gap.s),
          FilledButton(
            onPressed: _busy || !result.canPublish ? null : () => _save(context, s, publish: true, warnings: result.warnings.length),
            child: const Text('Publish'),
          ),
          const SizedBox(width: Gap.l),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(Gap.l),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: table),
                  const SizedBox(width: Gap.l),
                  Expanded(flex: 2, child: side),
                ],
              )
            : Column(
                children: [
                  Expanded(flex: 3, child: table),
                  const SizedBox(height: Gap.m),
                  Expanded(flex: 2, child: side),
                ],
              ),
      ),
    );
  }

  Future<void> _save(BuildContext context, AppState s, {required bool publish, int warnings = 0}) async {
    final draft = _draft();
    if (publish) {
      final ok = await confirmAction(
        context,
        title: 'Publish version $_number?',
        message:
            'Students in ${widget.group.label} will see this timetable from ${_dateFmt.format(_from)}. '
            '${warnings > 0 ? '$warnings warning(s) remain; make sure they are expected. ' : ''}'
            'Any published version with an overlapping period will be archived (kept for rollback).',
        confirm: 'Publish',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    if (!context.mounted) return;
    final done = await adminAction(context, () async {
      await s.repo.saveDraftVersion(draft, s.actor);
      if (publish) {
        final latest = await s.repo.fetch(asAdmin: true);
        await s.repo.publishVersion(draft.copyWith(createdBy: s.actor.email), latest.versions, s.actor);
      }
    }, success: publish ? 'Version $_number published.' : 'Draft saved.');
    if (mounted) setState(() => _busy = false);
    if (done && publish && context.mounted) Navigator.pop(context);
  }

  Future<void> _import(BuildContext context, CampusData d) async {
    final controller = TextEditingController();
    var replace = true;
    ImportResult? preview;
    String? fileName;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Import timetable entries'),
          content: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upload a .csv or .json file, or paste its contents.\n'
                  'CSV header: weekday,start,end,kind,subject,faculty,room,batch,shared_note. '
                  'JSON: a list of entries, or an object with "entries".',
                ),
                const SizedBox(height: Gap.s),
                Wrap(
                  spacing: Gap.s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Choose file'),
                      onPressed: () async {
                        final file = await openFile(
                          acceptedTypeGroups: const [XTypeGroup(label: 'Timetable', extensions: TimetableImporter.supportedExtensions)],
                        );
                        if (file == null) return;
                        final text = await file.readAsString();
                        final importer = TimetableImporter(rooms: d.rooms, faculty: d.faculty);
                        setD(() {
                          fileName = file.name;
                          final ok = TimetableImporter.formatFor(file.name) != null;
                          controller.text = ok ? text : '';
                          preview = importer.parseFile(file.name, text, idPrefix: _newId());
                        });
                      },
                    ),
                    if (fileName != null) Text('File: $fileName', style: Theme.of(c).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: Gap.s),
                TextField(
                  controller: controller,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'weekday,start,end,kind,subject,faculty,room,batch\nMon,08:00,10:00,lab,SE,PRK,CL 401,B1',
                  ),
                ),
                Row(
                  children: [
                    Checkbox(value: replace, onChanged: (v) => setD(() => replace = v ?? true)),
                    const Text('Replace existing entries in this draft'),
                  ],
                ),
                if (preview != null) ...[
                  Text(
                    'Parsed ${preview!.entries.length} entr${preview!.entries.length == 1 ? 'y' : 'ies'}, ${preview!.errors.length} error(s).',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: preview!.errors.isEmpty ? CsColors.free : Theme.of(c).colorScheme.error,
                    ),
                  ),
                  for (final e in preview!.errors.take(8))
                    Text('• $e', style: TextStyle(color: Theme.of(c).colorScheme.error, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            OutlinedButton(
              onPressed: () {
                final importer = TimetableImporter(rooms: d.rooms, faculty: d.faculty);
                final text = controller.text.trim();
                setD(
                  () => preview = text.startsWith('[') || text.startsWith('{')
                      ? importer.parseJson(text)
                      : importer.parseCsv(text, idPrefix: _newId()),
                );
              },
              child: const Text('Preview'),
            ),
            FilledButton(
              onPressed: preview == null || !preview!.ok
                  ? null
                  : () {
                      setState(() {
                        _entries = [if (!replace) ..._entries, ...preview!.entries];
                        // A file upload replaces auto-generated provenance; a manually typed source is kept.
                        if (fileName != null && (_source == null || _source!.isEmpty || _source!.startsWith('Uploaded file: '))) {
                          _source = 'Uploaded file: $fileName';
                        }
                      });
                      Navigator.pop(c);
                    },
              child: const Text('Apply to draft'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _editEntry(BuildContext context, CampusData d, TimetableEntry? e) async {
    final result = await showDialog<TimetableEntry>(
      context: context,
      builder: (_) => _EntryDialog(data: d, group: widget.group, entry: e, newId: _newId()),
    );
    if (result == null) return;
    setState(() {
      final i = _entries.indexWhere((x) => x.id == result.id);
      i >= 0 ? _entries[i] = result : _entries.add(result);
    });
  }
}

class _EntryDialog extends StatefulWidget {
  final CampusData data;
  final AcademicGroup group;
  final TimetableEntry? entry;
  final String newId;
  const _EntryDialog({required this.data, required this.group, this.entry, required this.newId});
  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _form = GlobalKey<FormState>();
  late int _weekday = widget.entry?.weekday ?? 1;
  late int _start = widget.entry?.startMin ?? 8 * 60;
  late int _end = widget.entry?.endMin ?? 9 * 60;
  late EntryKind _kind = widget.entry?.kind ?? EntryKind.lecture;
  late String? _subject = widget.entry?.subjectCode;
  late String? _faculty = widget.entry?.facultyId;
  late String? _room = widget.entry?.roomId;
  late String? _batch = widget.entry?.batch;
  late final _shared = TextEditingController(text: widget.entry?.sharedNote ?? '');

  @override
  void dispose() {
    _shared.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final times = [for (var m = 7 * 60; m <= 21 * 60; m += 30) m];
    final rooms = d.rooms.where((r) => r.bookable).toList()..sort((a, b) => a.name.compareTo(b.name));
    return AlertDialog(
      title: Text(widget.entry == null ? 'Add entry' : 'Edit entry'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        initialValue: _weekday,
                        decoration: const InputDecoration(labelText: 'Day'),
                        items: [for (var i = 1; i <= 6; i++) DropdownMenuItem(value: i, child: Text(weekdayNames[i - 1]))],
                        onChanged: (v) => setState(() => _weekday = v!),
                      ),
                    ),
                    const SizedBox(width: Gap.s),
                    Expanded(
                      child: DropdownButtonFormField<EntryKind>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        initialValue: _kind,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: [for (final k in EntryKind.values) DropdownMenuItem(value: k, child: Text(k.wire))],
                        onChanged: (v) => setState(() => _kind = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.m),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        initialValue: times.contains(_start) ? _start : null,
                        decoration: const InputDecoration(labelText: 'Start'),
                        items: [for (final m in times) DropdownMenuItem(value: m, child: Text(formatHm(m)))],
                        onChanged: (v) => setState(() => _start = v!),
                      ),
                    ),
                    const SizedBox(width: Gap.s),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        initialValue: times.contains(_end) ? _end : null,
                        decoration: const InputDecoration(labelText: 'End'),
                        items: [for (final m in times) DropdownMenuItem(value: m, child: Text(formatHm(m)))],
                        onChanged: (v) => setState(() => _end = v!),
                        validator: (v) => (v ?? 0) <= _start ? 'End must be after start' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.m),
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _subject,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  items: [for (final x in d.subjects) DropdownMenuItem(value: x.code, child: Text('${x.code} · ${x.name}'))],
                  onChanged: (v) => setState(() => _subject = v),
                  validator: (v) => _kind.needsRoom && v == null ? 'Subject is required for ${_kind.wire}' : null,
                ),
                const SizedBox(height: Gap.m),
                DropdownButtonFormField<String?>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _faculty,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Faculty (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                    for (final f in d.faculty) DropdownMenuItem(value: f.id, child: Text('${f.name} (${f.initials.join('/')})')),
                  ],
                  onChanged: (v) => setState(() => _faculty = v),
                ),
                const SizedBox(height: Gap.m),
                DropdownButtonFormField<String?>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _room,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Room'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— none —')),
                    for (final r in rooms) DropdownMenuItem(value: r.id, child: Text('${r.name} · floor ${r.floorId}')),
                  ],
                  onChanged: (v) => setState(() => _room = v),
                ),
                const SizedBox(height: Gap.m),
                DropdownButtonFormField<String?>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _batch,
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Whole division')),
                    for (final b in widget.group.batches) DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: (v) => setState(() => _batch = v),
                ),
                const SizedBox(height: Gap.m),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _shared,
                  decoration: const InputDecoration(labelText: 'Combined-session note (optional)', hintText: 'e.g. Combined lab B2+C2'),
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
            final fac = widget.data.facultyById[_faculty];
            Navigator.pop(
              context,
              TimetableEntry(
                id: widget.entry?.id ?? widget.newId,
                weekday: _weekday,
                startMin: _start,
                endMin: _end,
                kind: _kind,
                subjectCode: _subject,
                facultyId: _faculty,
                facultyInitials: fac?.initials.firstOrNull,
                roomId: _room,
                roomLabel: _room,
                batch: _batch,
                sharedNote: _shared.text.trim().isEmpty ? null : _shared.text.trim(),
                cancelled: widget.entry?.cancelled ?? false,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
