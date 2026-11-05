import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/campus_data.dart';
import '../../domain/exam_validator.dart';
import '../../domain/models.dart';
import '../../domain/timetable_validator.dart';
import '../../domain/validators.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_shell.dart';

final _fmt = DateFormat('d MMM yyyy');

ValidationResult _validate(CampusData d, List<Exam> exams) {
  final w = d.termEndExamWindow;
  return validateExams(
    exams,
    groupIds: d.groups.map((g) => g.id).toSet(),
    electiveIds: d.electives.map((e) => e.id).toSet(),
    windowStart: w?.start,
    windowEnd: w?.end,
  );
}

class _AdminExamList extends StatefulWidget {
  final List<Exam> exams;
  final ValueChanged<Exam> onEdit;
  const _AdminExamList({required this.exams, required this.onEdit});
  @override
  State<_AdminExamList> createState() => _AdminExamListState();
}

class _AdminExamListState extends State<_AdminExamList> {
  String _filter = 'linked';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final check = _validate(d, widget.exams);
    final byId = <String, List<ValidationIssue>>{};
    for (final i in check.issues) {
      if (i.entryId != null) (byId[i.entryId!] ??= []).add(i);
    }
    bool linked(Exam e) => e.groupIds.isNotEmpty || e.electiveOfferingIds.isNotEmpty;
    final shown = widget.exams.where((e) {
      final ok = switch (_filter) {
        'linked' => linked(e) && e.status != PublishStatus.archived,
        'unlinked' => !linked(e),
        'draft' => e.status == PublishStatus.draft,
        'withdrawn' => e.status == PublishStatus.archived,
        _ => true,
      };
      final q = _q.toLowerCase();
      return ok && (q.isEmpty || '${e.subjectName} ${e.officialCode ?? ''} ${e.stream ?? ''}'.toLowerCase().contains(q));
    }).toList();
    final jobs = d.importJobs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Gap.s),
        if (jobs.isNotEmpty)
          Text(
            'Import: ${jobs.first['sourceFile']} (pages ${jobs.first['pagesImported']}), imported ${jobs.first['importedOn']}: '
            '${(jobs.first['counts'] as Map?)?['records']} records, ${(jobs.first['warnings'] as List?)?.length ?? 0} review item(s).',
            style: t.textTheme.bodySmall,
          ),
        const SizedBox(height: Gap.s),
        Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (k, l) in const [
              ('linked', 'Visible to groups'),
              ('unlinked', 'Unlinked streams'),
              ('draft', 'Drafts'),
              ('withdrawn', 'Withdrawn'),
              ('all', 'All'),
            ])
              ChoiceChip(label: Text(l), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(hintText: 'Search subject, code, stream', prefixIcon: Icon(Icons.search), isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Pill('${check.errors.length} errors', color: check.errors.isEmpty ? CsColors.mint : t.colorScheme.error),
            Pill('${check.warnings.length} warnings', color: CsColors.partial),
          ],
        ),
        const SizedBox(height: Gap.s),
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(icon: Icons.edit_note_rounded, title: 'No exams', message: 'No exam records match this filter.')
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (c, i) {
                    final e = shown[i];
                    final issues = byId[e.id] ?? const [];
                    final hasError = issues.any((x) => x.level == IssueLevel.error);
                    final targets = [
                      ...e.groupIds.map((g) => d.groupsById[g]?.label ?? g),
                      ...e.electiveOfferingIds.map((o) => 'Elective: ${d.electivesById[o]?.name ?? o}'),
                    ];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.s),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            hasError ? Icons.error_outline : (issues.isNotEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                            color: hasError ? t.colorScheme.error : (issues.isNotEmpty ? CsColors.partial : CsColors.mint),
                          ),
                          const SizedBox(width: Gap.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${e.subjectName}${e.officialCode != null ? ' (${e.officialCode})' : ''}',
                                  style: t.textTheme.titleSmall,
                                ),
                                Text(
                                  style: t.textTheme.bodySmall,
                                  [
                                    '${_fmt.format(e.date)} · ${e.startTime ?? '?'}–${e.endTime ?? '?'}',
                                    if (e.stream != null) e.stream!,
                                    targets.isEmpty ? 'Not linked to any group' : targets.join(', '),
                                    ...issues.map((x) => x.message),
                                  ].join(' · '),
                                ),
                                Wrap(
                                  spacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Pill(
                                      e.status == PublishStatus.archived ? 'withdrawn' : e.status.name,
                                      color: switch (e.status) {
                                        PublishStatus.published => CsColors.mint,
                                        PublishStatus.draft => CsColors.partial,
                                        _ => CsColors.unavailable,
                                      },
                                    ),
                                    if (e.status != PublishStatus.published)
                                      TextButton(
                                        onPressed: hasError
                                            ? null
                                            : () async {
                                                if (await confirmAction(
                                                  context,
                                                  title: 'Publish exam?',
                                                  message:
                                                      '${e.subjectName} on ${_fmt.format(e.date)} becomes visible to: ${targets.isEmpty ? 'nobody (unlinked)' : targets.join(', ')}.',
                                                  confirm: 'Publish',
                                                )) {
                                                  if (context.mounted) {
                                                    await adminAction(
                                                      context,
                                                      () => s.repo.saveExam(e.copyWith(status: PublishStatus.published), s.actor),
                                                      success: 'Exam published.',
                                                    );
                                                  }
                                                }
                                              },
                                        child: const Text('Publish'),
                                      )
                                    else
                                      TextButton(
                                        onPressed: () async {
                                          if (await confirmAction(
                                            context,
                                            title: 'Withdraw exam?',
                                            message:
                                                'Students will no longer see ${e.subjectName} on ${_fmt.format(e.date)}. The record is kept.',
                                            confirm: 'Withdraw',
                                            destructive: true,
                                          )) {
                                            if (context.mounted) {
                                              await adminAction(
                                                context,
                                                () => s.repo.saveExam(e.copyWith(status: PublishStatus.archived), s.actor),
                                                success: 'Exam withdrawn.',
                                              );
                                            }
                                          }
                                        },
                                        child: const Text('Withdraw'),
                                      ),
                                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => widget.onEdit(e)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) =>
    showDatePicker(context: context, initialDate: initial ?? DateTime.now(), firstDate: DateTime(2025), lastDate: DateTime(2030));

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;
  const _DateField({required this.label, required this.value, required this.onChanged, this.required = false});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final d = await _pickDate(context, value);
      if (d != null) onChanged(d);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        suffixIcon: value != null && !required
            ? IconButton(tooltip: 'Clear', icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
            : const Icon(Icons.event_rounded),
      ),
      child: Text(value == null ? 'Not set' : _fmt.format(value!)),
    ),
  );
}

// ---------------------------------------------------------- announcements --
class AdminAnnouncements extends StatelessWidget {
  const AdminAnnouncements({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final items = [...d.announcements]..sort((a, b) => a.status.index.compareTo(b.status.index));
    return AdminPage(
      title: 'Announcements',
      subtitle: 'Only published announcements are visible to their target audience.',
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('New announcement'),
          onPressed: () => _edit(context, d, null),
        ),
      ],
      child: ListView(
        children: [
          for (final a in items)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.s),
              child: SectionCard(
                onTap: () => _edit(context, d, a),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            children: [
                              Pill(
                                a.status.name,
                                color: switch (a.status) {
                                  PublishStatus.published => CsColors.mint,
                                  PublishStatus.draft => CsColors.partial,
                                  _ => CsColors.unavailable,
                                },
                              ),
                              Pill(a.category, color: Theme.of(context).colorScheme.primary),
                              Pill(
                                a.audience.scope == 'all' ? 'All students' : '${a.audience.scope}: ${a.audience.ids.length}',
                                color: CsColors.lilac,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(a.title, style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            [
                              if (a.startDate != null) 'From ${_fmt.format(a.startDate!)}',
                              if (a.endDate != null) 'until ${_fmt.format(a.endDate!)}',
                              ...a.reviewFlags,
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _edit(BuildContext context, CampusData d, Announcement? a) => Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppState>(),
        child: AnnouncementEditor(existing: a),
      ),
    ),
  );
}

class AnnouncementEditor extends StatefulWidget {
  final Announcement? existing;
  const AnnouncementEditor({super.key, this.existing});
  @override
  State<AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<AnnouncementEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _summary = TextEditingController(text: widget.existing?.summary);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _url = TextEditingController(text: widget.existing?.registrationUrl);
  late final _image = TextEditingController(text: widget.existing?.imageUrl);
  late final _source = TextEditingController(text: widget.existing?.source);
  late String _category = widget.existing?.category ?? 'event';
  late DateTime? _start = widget.existing?.startDate;
  late DateTime? _end = widget.existing?.endDate;
  late String _scope = widget.existing?.audience.scope ?? 'all';
  late Set<String> _ids = {...?widget.existing?.audience.ids};

  static const categories = ['event', 'competition', 'internship', 'academic', 'general'];

  @override
  void dispose() {
    for (final c in [_title, _summary, _desc, _url, _image, _source]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Announcement _build(PublishStatus status) => Announcement(
    id: widget.existing?.id ?? 'ann-${DateTime.now().millisecondsSinceEpoch}',
    title: _title.text.trim(),
    status: status,
    category: _category,
    summary: _opt(_summary),
    description: _opt(_desc),
    startDate: _start,
    endDate: _end,
    registrationUrl: _opt(_url),
    imageUrl: _opt(_image),
    audience: AnnouncementAudience(scope: _scope, ids: _scope == 'all' ? const [] : _ids.toList()),
    source: _opt(_source),
    updatedAt: DateTime.now(),
    reviewFlags: status == PublishStatus.published ? const [] : (widget.existing?.reviewFlags ?? const []),
  );

  Future<void> _save(PublishStatus status) async {
    if (!_form.currentState!.validate()) return;
    final rangeErr = Validators.dateRange(_start, _end);
    if (rangeErr != null) {
      showMessage(context, rangeErr, error: true);
      return;
    }
    if (_scope != 'all' && _ids.isEmpty) {
      showMessage(context, 'Select at least one audience target.', error: true);
      return;
    }
    if (status == PublishStatus.published) {
      final ok = await confirmAction(
        context,
        title: 'Publish announcement?',
        message: 'It becomes visible to the selected audience on their next sync.',
        confirm: 'Publish',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    final s = context.read<AppState>();
    final done = await adminAction(
      context,
      () => s.repo.saveAnnouncement(_build(status), s.actor),
      success: 'Announcement ${status.name}.',
    );
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final preview = _build(PublishStatus.draft);
    final form = Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title *', hintText: 'e.g. Qiskit Fall Fest 2026 at MPSTME'),
            validator: Validators.title,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Gap.m),
          DropdownButtonFormField<String>(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            initialValue: categories.contains(_category) ? _category : 'general',
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: Gap.m),
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _summary,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Short summary', hintText: 'One line shown in lists'),
            onChanged: (_) => setState(() {}),
          ),
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _desc,
            maxLines: 6,
            maxLength: 5000, // same limit as the security rules
            decoration: const InputDecoration(labelText: 'Description', hintText: 'Full details, eligibility as officially stated'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Gap.m),
          Row(
            children: [
              Expanded(
                child: _DateField(label: 'Start date', value: _start, onChanged: (v) => setState(() => _start = v)),
              ),
              const SizedBox(width: Gap.s),
              Expanded(
                child: _DateField(label: 'End / deadline', value: _end, onChanged: (v) => setState(() => _end = v)),
              ),
            ],
          ),
          const SizedBox(height: Gap.m),
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Registration link',
              hintText: 'https://…',
              helperText: 'Shown to students as "Open official link". State the registration status in the description.',
            ),
            validator: Validators.optionalUrl,
          ),
          const SizedBox(height: Gap.m),
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _image,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Image URL (https, optional)', hintText: 'https://…'),
            validator: Validators.optionalUrl,
          ),
          const SizedBox(height: Gap.m),
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _source,
            maxLength: 300, // same limit as the security rules
            decoration: const InputDecoration(labelText: 'Source', hintText: 'Where this information comes from'),
          ),
          const SizedBox(height: Gap.l),
          Text('Audience', style: t.textTheme.titleSmall),
          const SizedBox(height: Gap.s),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All students')),
              ButtonSegment(value: 'department', label: Text('Departments')),
              ButtonSegment(value: 'groups', label: Text('Divisions')),
            ],
            selected: {_scope},
            onSelectionChanged: (v) => setState(() {
              _scope = v.first;
              _ids = {};
            }),
          ),
          const SizedBox(height: Gap.s),
          if (_scope != 'all')
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                for (final (id, label)
                    in _scope == 'department' ? d.departments.map((x) => (x.id, x.name)) : d.divisionGroups.map((x) => (x.id, x.label)))
                  FilterChip(
                    label: Text(label),
                    selected: _ids.contains(id),
                    onSelected: (v) => setState(() => v ? _ids.add(id) : _ids.remove(id)),
                  ),
              ],
            ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New announcement' : 'Edit announcement'),
        actions: [
          if (widget.existing != null && widget.existing!.status != PublishStatus.archived)
            TextButton(
              onPressed: () async {
                if (await confirmAction(
                  context,
                  title: 'Archive?',
                  message: 'Students will no longer see this announcement.',
                  confirm: 'Archive',
                  destructive: true,
                )) {
                  _save(PublishStatus.archived);
                }
              },
              child: const Text('Archive'),
            ),
          TextButton(onPressed: () => _save(PublishStatus.draft), child: const Text('Save draft')),
          const SizedBox(width: Gap.s),
          FilledButton(onPressed: () => _save(PublishStatus.published), child: const Text('Publish')),
          const SizedBox(width: Gap.l),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final previewCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Student preview', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
                  const SizedBox(height: Gap.m),
                  Pill(preview.category, color: t.colorScheme.primary),
                  const SizedBox(height: Gap.s),
                  Text(preview.title.isEmpty ? 'Title' : preview.title, style: t.textTheme.titleLarge),
                  if (preview.endDate != null) Text('Ends ${_fmt.format(preview.endDate!)}', style: t.textTheme.bodySmall),
                  const SizedBox(height: Gap.s),
                  Text(preview.description ?? preview.summary ?? 'No description', style: t.textTheme.bodyMedium),
                ],
              ),
            ),
          );
          if (c.maxWidth > 1000) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: form),
                Expanded(
                  flex: 2,
                  child: Padding(padding: const EdgeInsets.all(Gap.l), child: previewCard),
                ),
              ],
            );
          }
          return form;
        },
      ),
    );
  }
}

// ------------------------------------------------------ exams & calendar --
class AdminExamsCalendar extends StatelessWidget {
  const AdminExamsCalendar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    final exams = [...d.exams]..sort((a, b) => a.date.compareTo(b.date));
    final events = [...d.calendarEvents]..sort((a, b) => a.start.compareTo(b.start));
    return DefaultTabController(
      length: 2,
      child: AdminPage(
        title: 'Exams & academic calendar',
        subtitle: 'Subject exam dates are kept separate from calendar date ranges.',
        actions: [
          OutlinedButton.icon(icon: const Icon(Icons.add_rounded), label: const Text('Exam'), onPressed: () => _editExam(context, d, null)),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Calendar event'),
            onPressed: () => _editEvent(context, d, null),
          ),
        ],
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Exams'),
                Tab(text: 'Calendar'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AdminExamList(exams: exams, onEdit: (e) => _editExam(context, d, e)),
                  ListView(
                    children: [
                      for (final e in events)
                        ListTile(
                          title: Text(e.title),
                          subtitle: Text(
                            '${_fmt.format(e.start)} – ${_fmt.format(e.end)} · ${e.category} · ${d.calendarAudienceLabels[e.audience] ?? e.audience}',
                            style: t.textTheme.bodySmall,
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editEvent(context, d, e),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  if (await confirmAction(
                                    context,
                                    title: 'Delete event?',
                                    message: e.title,
                                    confirm: 'Delete',
                                    destructive: true,
                                  )) {
                                    if (context.mounted) {
                                      await adminAction(
                                        context,
                                        () => s.repo.deleteCalendarEvent(e.id, s.actor),
                                        success: 'Event deleted.',
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editExam(BuildContext context, CampusData d, Exam? e) async {
    final s = context.read<AppState>();
    final result = await showDialog<Exam>(
      context: context,
      builder: (_) => _ExamDialog(data: d, exam: e),
    );
    if (result == null || !context.mounted) return;
    final check = _validate(d, [
      for (final x in d.exams)
        if (x.id != result.id) x,
      result,
    ]);
    final mine = check.issues.where((i) => i.entryId == result.id).toList();
    final errors = mine.where((i) => i.level == IssueLevel.error).toList();
    if (errors.isNotEmpty) {
      showMessage(context, 'Not saved: ${errors.map((i) => i.message).join(' ')}', error: true);
      return;
    }
    final warnings = mine.where((i) => i.level == IssueLevel.warning).toList();
    if (warnings.isNotEmpty &&
        !await confirmAction(
          context,
          title: 'Save with warnings?',
          message: warnings.map((i) => '• ${i.message}').join('\n'),
          confirm: 'Save',
        )) {
      return;
    }
    if (context.mounted) await adminAction(context, () => s.repo.saveExam(result, s.actor), success: 'Exam saved.');
  }

  Future<void> _editEvent(BuildContext context, CampusData d, CalendarEvent? e) async {
    final s = context.read<AppState>();
    final result = await showDialog<CalendarEvent>(
      context: context,
      builder: (_) => _EventDialog(data: d, event: e),
    );
    if (result == null || !context.mounted) return;
    final dup = d.calendarEvents.where(
      (x) => x.id != result.id && x.title == result.title && x.audience == result.audience && x.start == result.start,
    );
    if (dup.isNotEmpty) {
      showMessage(context, 'An identical event already exists for this audience.', error: true);
      return;
    }
    await adminAction(context, () => s.repo.saveCalendarEvent(result, s.actor), success: 'Calendar event saved.');
  }
}

class _ExamDialog extends StatefulWidget {
  final CampusData data;
  final Exam? exam;
  const _ExamDialog({required this.data, this.exam});
  @override
  State<_ExamDialog> createState() => _ExamDialogState();
}

class _ExamDialogState extends State<_ExamDialog> {
  String? _formError; // shown inside the dialog (snackbars sit behind the modal barrier)
  final _form = GlobalKey<FormState>();
  late String? _subject = widget.exam?.subjectCode;
  late final Set<String> _groups = {...?widget.exam?.groupIds};
  late DateTime? _date = widget.exam?.date;
  late final _start = TextEditingController(text: widget.exam?.startTime);
  late final _end = TextEditingController(text: widget.exam?.endTime);
  late final _session = TextEditingController(text: widget.exam?.session);
  late final _source = TextEditingController(text: widget.exam?.source);

  String? _time(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    try {
      parseHm(v);
      return null;
    } on FormatException {
      return 'Use HH:MM (24-hour)';
    }
  }

  @override
  void dispose() {
    for (final c in [_start, _end, _session, _source]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return AlertDialog(
      title: Text(widget.exam == null ? 'Add exam' : 'Edit exam'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _subject,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Subject *'),
                  items: [
                    for (final x in d.subjects.where((x) => !x.code.startsWith('OE')))
                      DropdownMenuItem(value: x.code, child: Text('${x.code} · ${x.name}')),
                    if (widget.exam != null && !d.subjectsByCode.containsKey(widget.exam!.subjectCode) ||
                        (widget.exam?.subjectCode.startsWith('OE') ?? false))
                      DropdownMenuItem(
                        value: widget.exam!.subjectCode,
                        child: Text('${widget.exam!.subjectCode} · ${widget.exam!.subjectName}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _subject = v),
                  validator: (v) => v == null ? 'Select a subject.' : null,
                ),
                const SizedBox(height: Gap.m),
                const Text('Academic groups *'),
                Wrap(
                  spacing: Gap.s,
                  children: [
                    for (final g in d.divisionGroups)
                      FilterChip(
                        label: Text(g.label),
                        selected: _groups.contains(g.id),
                        onSelected: (v) => setState(() => v ? _groups.add(g.id) : _groups.remove(g.id)),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.m),
                _DateField(label: 'Exam date', value: _date, required: true, onChanged: (v) => setState(() => _date = v)),
                const SizedBox(height: Gap.m),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        controller: _start,
                        decoration: const InputDecoration(labelText: 'Start (optional)', hintText: 'HH:MM'),
                        validator: _time,
                      ),
                    ),
                    const SizedBox(width: Gap.s),
                    Expanded(
                      child: TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        controller: _end,
                        decoration: const InputDecoration(labelText: 'End (optional)', hintText: 'HH:MM'),
                        validator: (v) {
                          final e = _time(v);
                          if (e != null || v == null || v.trim().isEmpty || _time(_start.text) != null || _start.text.trim().isEmpty) {
                            return e;
                          }
                          return parseHm(v) <= parseHm(_start.text) ? 'End must be after start' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.m),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _session,
                  decoration: const InputDecoration(labelText: 'Session (optional)', hintText: 'e.g. Morning'),
                ),
                const SizedBox(height: Gap.m),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _source,
                  decoration: const InputDecoration(
                    labelText: 'Source *',
                    hintText: 'e.g. Odd Semester Final Exam Timetable 2026-27, page 3',
                  ),
                  validator: (v) => Validators.required(v, 'Source'),
                ),
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.m),
                    child: Text(
                      _formError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
                    ),
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
            final electives = widget.exam?.electiveOfferingIds ?? const <String>[];
            if ((_groups.isEmpty && electives.isEmpty) || _date == null) {
              setState(() => _formError = 'Select at least one group and a date.');
              return;
            }
            String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
            Navigator.pop(
              context,
              Exam(
                id: widget.exam?.id ?? 'exam-${DateTime.now().millisecondsSinceEpoch}',
                groupIds: _groups.toList(),
                electiveOfferingIds: electives,
                subjectCode: _subject!,
                // Keep the record's own name (e.g. a specific elective) unless the subject was changed.
                subjectName: widget.exam != null && _subject == widget.exam!.subjectCode
                    ? widget.exam!.subjectName
                    : d.subjectsByCode[_subject]?.name ?? _subject!,
                officialCode: widget.exam?.officialCode,
                stream: widget.exam?.stream,
                date: _date!,
                startTime: opt(_start),
                endTime: opt(_end),
                timeSource: widget.exam == null ? 'cell' : widget.exam!.timeSource,
                session: opt(_session),
                room: widget.exam?.room,
                // New exams start as drafts; edits keep the current status.
                status: widget.exam?.status ?? PublishStatus.draft,
                source: opt(_source),
                reviewFlags: widget.exam?.reviewFlags ?? const [],
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EventDialog extends StatefulWidget {
  final CampusData data;
  final CalendarEvent? event;
  const _EventDialog({required this.data, this.event});
  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  String? _formError; // shown inside the dialog (snackbars sit behind the modal barrier)
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.event?.title);
  late String _category = widget.event?.category ?? 'midterm';
  late String _term = widget.event?.term ?? 'odd';
  late String _audience = widget.event?.audience ?? widget.data.calendarAudienceLabels.keys.first;
  late DateTime? _start = widget.event?.start;
  late DateTime? _end = widget.event?.end;

  static const categories = ['term', 'midterm', 'termEndExam', 'labExam', 'reExam', 'vacation', 'event'];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.event == null ? 'Add calendar event' : 'Edit calendar event'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  validator: Validators.title,
                ),
                const SizedBox(height: Gap.m),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        initialValue: categories.contains(_category) ? _category : 'event',
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
                        onChanged: (v) => setState(() => _category = v!),
                      ),
                    ),
                    const SizedBox(width: Gap.s),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        initialValue: _term,
                        decoration: const InputDecoration(labelText: 'Term'),
                        items: const [
                          DropdownMenuItem(value: 'odd', child: Text('Odd')),
                          DropdownMenuItem(value: 'even', child: Text('Even')),
                          DropdownMenuItem(value: 'next', child: Text('Next year')),
                        ],
                        onChanged: (v) => setState(() => _term = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.m),
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _audience,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: [
                    for (final e in widget.data.calendarAudienceLabels.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _audience = v!),
                ),
                const SizedBox(height: Gap.m),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(label: 'Start', value: _start, required: true, onChanged: (v) => setState(() => _start = v)),
                    ),
                    const SizedBox(width: Gap.s),
                    Expanded(
                      child: _DateField(label: 'End', value: _end, required: true, onChanged: (v) => setState(() => _end = v)),
                    ),
                  ],
                ),
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.m),
                    child: Text(
                      _formError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
                    ),
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
            final err = _start == null || _end == null ? 'Start and end dates are required.' : Validators.dateRange(_start, _end);
            if (err != null) {
              setState(() => _formError = err);
              return;
            }
            Navigator.pop(
              context,
              CalendarEvent(
                id: widget.event?.id ?? 'cal-${DateTime.now().millisecondsSinceEpoch}',
                title: _title.text.trim(),
                category: _category,
                start: _start!,
                end: _end!,
                term: _term,
                audience: _audience,
                source: widget.event?.source ?? 'Entered by administrator',
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
