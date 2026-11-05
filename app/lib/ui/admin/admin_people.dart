import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_shell.dart';

/// Loads a list from the repository with retry and empty/error states.
class _AsyncList<T> extends StatefulWidget {
  final Future<List<T>> Function() load;
  final Widget Function(BuildContext, List<T>, VoidCallback reload) builder;
  const _AsyncList({required this.load, required this.builder});
  @override
  State<_AsyncList<T>> createState() => _AsyncListState<T>();
}

class _AsyncListState<T> extends State<_AsyncList<T>> {
  late Future<List<T>> _future = widget.load();
  void _reload() => setState(() {
    _future = widget.load();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<List<T>>(
    future: _future,
    builder: (c, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) {
        return EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load',
          message: '${snap.error}',
          action: FilledButton(onPressed: _reload, child: const Text('Retry')),
        );
      }
      return widget.builder(c, snap.data!, _reload);
    },
  );
}

class AdminStudents extends StatefulWidget {
  const AdminStudents({super.key});
  @override
  State<AdminStudents> createState() => _AdminStudentsState();
}

class _AdminStudentsState extends State<AdminStudents> {
  String _filter = 'pending';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data!;
    final t = Theme.of(context);
    return AdminPage(
      title: 'Students',
      subtitle:
          'Only the sign-in email is verified (by Firebase Authentication). Name, SAP ID, roll number and division are typed by the student '
          'and not checked against any university roster: confirm them with college records or the student ID card before approving. '
          'Identifiers are private to administrators.',
      child: _AsyncList<StudentProfile>(
        load: s.repo.listStudents,
        builder: (context, all, reload) {
          final items = all
              .where((p) => p.status.name == _filter)
              .where((p) => _q.isEmpty || '${p.displayName} ${p.sapId} ${p.rollNumber} ${p.email}'.toLowerCase().contains(_q.toLowerCase()))
              .toList();
          return Column(
            children: [
              Wrap(
                spacing: Gap.m,
                runSpacing: Gap.s,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: [
                      for (final st in AccountStatus.values)
                        ButtonSegment(value: st.name, label: Text('${st.name} (${all.where((p) => p.status == st).length})')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) => setState(() => _filter = v.first),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'Search name, SAP ID, roll, email', prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                  IconButton(tooltip: 'Reload', onPressed: reload, icon: const Icon(Icons.refresh)),
                ],
              ),
              const SizedBox(height: Gap.m),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        icon: Icons.school_outlined,
                        title: 'No $_filter students',
                        message: s.isDemo
                            ? 'Demo mode has no student accounts; registration requires Firebase.'
                            : 'Nothing to review here.',
                      )
                    : ListView(
                        children: [
                          for (final p in items)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(Gap.m),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${p.displayName} · ${p.rollNumber}', style: t.textTheme.titleSmall),
                                    Text('Sign-in email (verified): ${p.email}', style: t.textTheme.bodySmall),
                                    Text(
                                      'Self-declared, unverified: SAP ${p.sapId} · Roll ${p.rollNumber} · '
                                      'Requested ${d.groupsById[p.requestedGroupId]?.label ?? p.requestedGroupId ?? '—'}'
                                      '${p.groupId != null ? '\nAssigned: ${d.groupsById[p.groupId]?.label ?? p.groupId}' : ''}',
                                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                                    ),
                                    if (p.sapReleased)
                                      Text(
                                        'SAP ID released: this account no longer holds ${p.sapId} and cannot be approved.',
                                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error),
                                      ),
                                    const SizedBox(height: Gap.s),
                                    Wrap(
                                      spacing: Gap.s,
                                      runSpacing: Gap.s,
                                      children: [
                                        if (p.status != AccountStatus.active && !p.sapReleased)
                                          FilledButton(onPressed: () => _approve(context, s, p, reload), child: const Text('Approve')),
                                        if (p.status != AccountStatus.suspended)
                                          OutlinedButton(
                                            onPressed: () async {
                                              if (await confirmAction(
                                                context,
                                                title: 'Suspend ${p.displayName}?',
                                                message: 'They will lose access to campus data.',
                                                confirm: 'Suspend',
                                                destructive: true,
                                              )) {
                                                if (context.mounted) {
                                                  await adminAction(
                                                    context,
                                                    () => s.repo.setStudentAccount(
                                                      p.uid,
                                                      status: AccountStatus.suspended,
                                                      groupId: p.groupId,
                                                      actor: s.actor,
                                                    ),
                                                    success: 'Student suspended.',
                                                  );
                                                }
                                                reload();
                                              }
                                            },
                                            child: Text('Suspend', style: TextStyle(color: t.colorScheme.error)),
                                          ),
                                        // Already released: nothing left to release.
                                        if (p.status != AccountStatus.active && !p.sapReleased)
                                          TextButton(
                                            onPressed: () => _releaseSap(context, s, p, reload),
                                            child: Text('Release SAP ID', style: TextStyle(color: t.colorScheme.error)),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Recovery when an account claimed a SAP ID that is not theirs.
  Future<void> _releaseSap(BuildContext context, AppState s, StudentProfile p, VoidCallback reload) async {
    if (await confirmAction(
      context,
      title: 'Release SAP ID ${p.sapId}?',
      message:
          'Use this when ${p.email} registered with a SAP ID that is not theirs. The account is suspended permanently '
          'and the SAP ID becomes free, so the rightful student can register. This is recorded in the audit log.',
      confirm: 'Suspend and release',
      destructive: true,
    )) {
      if (!context.mounted) return;
      // The list may be stale (another admin, or a second click): the
      // repository re-checks and reports instead of failing with a raw error.
      try {
        final outcome = await s.repo.releaseSapId(p, s.actor);
        await s.refresh();
        if (context.mounted) {
          showMessage(
            context,
            outcome == SapRelease.released
                ? 'SAP ID released; account suspended.'
                : 'SAP ID ${p.sapId} was already released for ${p.email}. Nothing changed.',
          );
        }
      } on RepositoryException catch (e) {
        if (context.mounted) showMessage(context, e.message, error: true);
      } catch (e) {
        if (context.mounted) showMessage(context, 'Failed: $e', error: true);
      }
      reload();
    }
  }

  Future<void> _approve(BuildContext context, AppState s, StudentProfile p, VoidCallback reload) async {
    final d = s.data!;
    String? group = p.groupId ?? p.requestedGroupId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Approve ${p.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sign-in email (verified): ${p.email}'),
              Text('SAP ID ${p.sapId} · Roll ${p.rollNumber}'),
              const SizedBox(height: Gap.s),
              Text(
                'SAP ID, roll number and name are self-declared. Check them against college records before approving.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
              const SizedBox(height: Gap.m),
              DropdownButtonFormField<String>(
                initialValue: d.groupsById.containsKey(group) ? group : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Assign academic group'),
                itemHeight: null,
                items: [for (final g in d.divisionGroups) DropdownMenuItem(value: g.id, child: Text(g.label, maxLines: 2, softWrap: true))],
                onChanged: (v) => setD(() => group = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: group == null ? null : () => Navigator.pop(c, true), child: const Text('Approve')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await adminAction(
        context,
        () => s.repo.setStudentAccount(p.uid, status: AccountStatus.active, groupId: group, actor: s.actor),
        success: 'Student approved.',
      );
      reload();
    }
  }
}

class AdminAdmins extends StatelessWidget {
  const AdminAdmins({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return AdminPage(
      title: 'Administrators',
      subtitle:
          'Admins have full access; content managers can manage announcements, exams and calendar only. You cannot change your own role.',
      child: _AsyncList<AdminAccount>(
        load: s.repo.listAdmins,
        builder: (context, admins, reload) => ListView(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Grant access'),
                onPressed: () => _grant(context, s, reload),
              ),
            ),
            const SizedBox(height: Gap.m),
            for (final a in admins)
              Card(
                child: ListTile(
                  leading: Icon(a.role == AdminRole.admin ? Icons.admin_panel_settings_rounded : Icons.edit_note_rounded),
                  title: Text(a.email),
                  subtitle: Text('${a.role?.name ?? 'invalid role (no access)'} · ${a.uid}'),
                  trailing: a.uid == s.actor.uid
                      ? const Pill('you', color: CsColors.seed)
                      : TextButton(
                          onPressed: () async {
                            if (await confirmAction(
                              context,
                              title: 'Revoke access for ${a.email}?',
                              message: 'They will lose all administrative access.',
                              confirm: 'Revoke',
                              destructive: true,
                            )) {
                              if (context.mounted) {
                                await adminAction(
                                  context,
                                  () => s.repo.setAdmin(a.uid, a.email, null, s.actor),
                                  success: 'Access revoked.',
                                );
                              }
                              reload();
                            }
                          },
                          child: const Text('Revoke'),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _grant(BuildContext context, AppState s, VoidCallback reload) async {
    final uid = TextEditingController();
    final email = TextEditingController();
    var role = AdminRole.contentManager;
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Grant administrative access'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('The person must first create an account. Copy their user ID (UID) from the Students list or Firebase console.'),
                const SizedBox(height: Gap.m),
                TextFormField(
                  controller: uid,
                  decoration: const InputDecoration(labelText: 'User ID (UID) *'),
                  validator: (v) => RegExp(r'^[A-Za-z0-9]{10,128}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid UID',
                ),
                const SizedBox(height: Gap.m),
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email (for display) *'),
                  validator: (v) => (v ?? '').contains('@') ? null : 'Enter an email',
                ),
                const SizedBox(height: Gap.m),
                SegmentedButton<AdminRole>(
                  segments: const [
                    ButtonSegment(value: AdminRole.contentManager, label: Text('Content manager')),
                    ButtonSegment(value: AdminRole.admin, label: Text('Admin')),
                  ],
                  selected: {role},
                  onSelectionChanged: (v) => setD(() => role = v.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(c, true) : null, child: const Text('Grant')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await adminAction(context, () => s.repo.setAdmin(uid.text.trim(), email.text.trim(), role, s.actor), success: 'Access granted.');
      reload();
    }
    uid.dispose();
    email.dispose();
  }
}

class AdminAudit extends StatelessWidget {
  const AdminAudit({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final fmt = DateFormat('d MMM yyyy, HH:mm');
    return AdminPage(
      title: 'Audit log',
      subtitle: 'Every administrative change is recorded with its actor and time. Entries cannot be edited or deleted.',
      child: _AsyncList<AuditRecord>(
        load: () => s.repo.listAudit(limit: 200),
        builder: (context, items, reload) => items.isEmpty
            ? const EmptyState(icon: Icons.history, title: 'No changes yet', message: 'Administrative actions will appear here.')
            : ListView(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(tooltip: 'Reload', onPressed: reload, icon: const Icon(Icons.refresh)),
                  ),
                  for (final a in items)
                    ListTile(
                      leading: const Icon(Icons.edit_note_rounded),
                      title: Text('${a.action} · ${a.targetPath}'),
                      subtitle: Text('${a.actorEmail} · ${fmt.format(a.at.toLocal())}${a.summary != null ? ' · ${a.summary}' : ''}'),
                    ),
                ],
              ),
      ),
    );
  }
}
