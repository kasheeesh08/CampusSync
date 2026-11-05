import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/local_cache.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../world/character.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final p = s.profile;
    final d = s.data;
    final group = s.myGroup;
    final prefs = s.prefs;
    String mask(String v) => v.length <= 4 ? v : '${'•' * (v.length - 4)}${v.substring(v.length - 4)}';

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xl, 0, Gap.s),
      child: Text(
        text.toUpperCase(),
        style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, letterSpacing: 1.2, fontWeight: FontWeight.w800),
      ),
    );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          Text('Me', style: t.textTheme.headlineSmall),
          const SizedBox(height: Gap.l),
          SectionCard(
            child: Row(
              children: [
                GestureDetector(onTap: () => _pickAvatar(context, s), child: AvatarBubble(p?.avatar ?? 'fox', size: 64)),
                const SizedBox(width: Gap.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p?.displayName.isNotEmpty == true ? p!.displayName : 'Student', style: t.textTheme.titleLarge),
                      Text(group?.label ?? 'No group assigned', style: t.textTheme.bodySmall),
                      if (p != null && p.sapId.isNotEmpty)
                        Text('SAP ${mask(p.sapId)} · Roll ${p.rollNumber}', style: t.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Edit name', icon: const Icon(Icons.edit_outlined), onPressed: () => _editName(context, s)),
              ],
            ),
          ),
          const SizedBox(height: Gap.s),
          SectionCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.face_retouching_natural_rounded),
              title: const Text('Customize character'),
              subtitle: const Text('Avatar and outfit shown on campus'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickAvatar(context, s),
            ),
          ),
          header('Academic profile'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Division'),
                  subtitle: Text(group?.label ?? '—'),
                  trailing: s.isDemo ? TextButton(onPressed: () => _changeDemoGroup(context, s), child: const Text('Change')) : null,
                ),
                if (group != null && group.batches.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: const Text('Lab batch'),
                    trailing: DropdownButton<String>(
                      value: group.batches.contains(p?.batch) ? p?.batch : null,
                      hint: const Text('Select'),
                      underline: const SizedBox.shrink(),
                      items: [for (final b in group.batches) DropdownMenuItem(value: b, child: Text(b))],
                      onChanged: (v) => _guard(context, () => s.updatePreferences({'batch': v})),
                    ),
                  ),
                for (final slot in const ['OE-1', 'OE-2'])
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(slot == 'OE-1' ? 'Open Elective I' : 'Open Elective II'),
                    subtitle: Text(d?.electivesById[slot == 'OE-1' ? p?.oe1OfferingId : p?.oe2OfferingId]?.name ?? 'Not selected'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: d == null ? null : () => _pickElective(context, s, slot),
                  ),
              ],
            ),
          ),
          header('Notifications'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.alarm_rounded),
                  title: const Text('Class reminders'),
                  subtitle: Text('${prefs.reminderLeadMinutes} min before each class'),
                  value: prefs.classReminders,
                  onChanged: (v) => _toggleNotif(context, s, prefs.copyWith(classReminders: v), v),
                ),
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: const Text('Reminder lead time'),
                  trailing: DropdownButton<int>(
                    value: prefs.reminderLeadMinutes,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final m in const [5, 10, 15, 30]) DropdownMenuItem(value: m, child: Text('$m min')),
                    ],
                    onChanged: (v) => s.setPrefs(prefs.copyWith(reminderLeadMinutes: v)),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.edit_note_rounded),
                  title: const Text('Exam reminders'),
                  subtitle: const Text('Evening before each published exam'),
                  value: prefs.examReminders,
                  onChanged: (v) => _toggleNotif(context, s, prefs.copyWith(examReminders: v), v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.bookmark_added_outlined),
                  title: const Text('Deadline reminders'),
                  subtitle: const Text('Day before saved announcements close'),
                  value: prefs.deadlineReminders,
                  onChanged: (v) => _toggleNotif(context, s, prefs.copyWith(deadlineReminders: v), v),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.m),
                  child: Text(
                    s.notifications.available
                        ? (s.notificationsBlocked
                              ? 'Notifications are turned off for CampusSync in Android settings, so reminders will not appear.'
                              : '${s.scheduledReminders} reminder(s) scheduled for the next 7 days. Android may delay reminders to save battery.')
                        : (s.notifications.supported
                              ? 'Reminders could not be started on this device.'
                              : 'Reminders are available in the Android app.'),
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
                // Exam/deadline reminders are on by default, so offer the permission
                // request directly instead of requiring a toggle off/on.
                if (s.notifications.available && s.notificationsBlocked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m),
                    child: TextButton.icon(
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Allow notifications'),
                      onPressed: () async {
                        final ok = await s.notifications.requestPermission();
                        if (!context.mounted) return;
                        if (!ok) {
                          showMessage(context, 'Notification permission was denied. Enable it in Android settings.', error: true);
                        }
                        await s.rescheduleReminders();
                      },
                    ),
                  ),
              ],
            ),
          ),
          header('Appearance & accessibility'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Theme'),
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined), tooltip: 'Light'),
                      ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined), tooltip: 'Dark'),
                      ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto_outlined), tooltip: 'System'),
                    ],
                    selected: {prefs.themeMode},
                    onSelectionChanged: (v) => s.setPrefs(prefs.copyWith(themeMode: v.first)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.format_size_rounded),
                  title: const Text('Text size'),
                  subtitle: Slider(
                    value: prefs.textScale,
                    min: 0.9,
                    max: 1.4,
                    divisions: 5,
                    label: '${(prefs.textScale * 100).round()}%',
                    onChanged: (v) => s.setPrefs(prefs.copyWith(textScale: v)),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.motion_photos_off_outlined),
                  title: const Text('Reduce motion'),
                  subtitle: const Text('Pause campus animations'),
                  value: prefs.reduceMotion,
                  onChanged: (v) => s.setPrefs(prefs.copyWith(reduceMotion: v)),
                ),
              ],
            ),
          ),
          header('Data'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(s.offline ? Icons.cloud_off_rounded : Icons.cloud_done_outlined),
              title: Text(s.syncLabel),
              subtitle: Text('${s.saved.length} saved announcement(s) available offline'),
              trailing: s.refreshing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(tooltip: 'Sync now', icon: const Icon(Icons.sync_rounded), onPressed: s.refresh),
            ),
          ),
          header('Account'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (!s.isDemo)
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Reset password'),
                    subtitle: Text(s.user?.email ?? ''),
                    onTap: () => _guard(context, () async {
                      await s.auth!.resetPassword(s.user!.email);
                      if (context.mounted) showMessage(context, 'Password reset email sent to ${s.user!.email}.');
                    }),
                  ),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: t.colorScheme.error),
                  title: Text(s.isDemo ? 'Leave demo' : 'Sign out', style: TextStyle(color: t.colorScheme.error)),
                  onTap: () async {
                    final ok = await confirmAction(
                      context,
                      title: s.isDemo ? 'Leave demo?' : 'Sign out?',
                      message: 'Cached timetables and saved announcements on this device will be cleared.',
                      confirm: s.isDemo ? 'Leave' : 'Sign out',
                      destructive: true,
                    );
                    if (ok) await s.signOut();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          Center(
            child: Text(
              'CampusSync 1.0 · Attendance tracking is not part of this release.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _guard(BuildContext context, Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      if (context.mounted) showMessage(context, 'Could not save: $e', error: true);
    }
  }

  Future<void> _toggleNotif(BuildContext context, AppState s, AppPreferences prefs, bool enabling) async {
    if (enabling && s.notifications.available) {
      await s.notifications.init(s.data?.settings.timezone ?? 'Asia/Kolkata');
      final ok = await s.notifications.requestPermission();
      if (!ok) {
        if (context.mounted) showMessage(context, 'Notification permission was denied. Enable it in Android settings.', error: true);
        return;
      }
    }
    await s.setPrefs(prefs);
  }

  /// Character customisation. The avatar is stored with the profile; the shirt
  /// colour is a cosmetic, device-local preference (never part of academic data).
  void _pickAvatar(BuildContext context, AppState s) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => Consumer<AppState>(
        builder: (c, st, _) {
          final t = Theme.of(c);
          final colorIndex = st.prefs.characterColor % characterColors.length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customize character', style: t.textTheme.titleLarge),
                  const SizedBox(height: Gap.m),
                  Center(
                    child: CampusCharacter(
                      avatar: st.profile?.avatar ?? 'fox',
                      color: characterColors[colorIndex],
                      size: 96,
                      reduceMotion: st.prefs.reduceMotion,
                    ),
                  ),
                  const SizedBox(height: Gap.m),
                  Text('Avatar', style: t.textTheme.labelLarge),
                  const SizedBox(height: Gap.s),
                  Wrap(
                    spacing: Gap.m,
                    runSpacing: Gap.m,
                    children: [
                      for (final a in avatars.keys)
                        Semantics(
                          button: true,
                          selected: a == st.profile?.avatar,
                          label: 'Avatar $a',
                          child: GestureDetector(
                            onTap: () => _guard(context, () => st.updatePreferences({'avatar': a})),
                            child: AvatarBubble(a, size: 48, selected: a == st.profile?.avatar),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.l),
                  Text('Outfit colour', style: t.textTheme.labelLarge),
                  const SizedBox(height: Gap.s),
                  Wrap(
                    spacing: Gap.m,
                    runSpacing: Gap.m,
                    children: [
                      for (var i = 0; i < characterColors.length; i++)
                        Semantics(
                          button: true,
                          selected: i == colorIndex,
                          label: 'Outfit colour ${i + 1}',
                          child: GestureDetector(
                            onTap: () => st.setPrefs(st.prefs.copyWith(characterColor: i)),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: characterColors[i],
                                shape: BoxShape.circle,
                                border: Border.all(color: i == colorIndex ? t.colorScheme.onSurface : Colors.transparent, width: 3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.m),
                  Text(
                    'Outfit colour is saved on this device only.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Gap.m),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editName(BuildContext context, AppState s) async {
    final controller = TextEditingController(text: s.profile?.displayName ?? '');
    final form = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Display name'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Your name'),
            validator: (v) => (v == null || v.trim().length < 2)
                ? 'Enter at least 2 characters.'
                : (v.trim().length > 50 ? 'At most 50 characters.' : null),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => form.currentState!.validate() ? Navigator.pop(c, controller.text.trim()) : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && context.mounted) await _guard(context, () => s.updatePreferences({'displayName': name}));
  }

  void _pickElective(BuildContext context, AppState s, String slot) {
    final d = s.data!;
    final options = d.electives.where((e) => e.slot == slot).toList()..sort((a, b) => a.name.compareTo(b.name));
    final key = slot == 'OE-1' ? 'oe1OfferingId' : 'oe2OfferingId';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              title: const Text('Not selected'),
              leading: const Icon(Icons.remove_circle_outline),
              onTap: () {
                Navigator.pop(c);
                _guard(context, () => s.updatePreferences({key: null}));
              },
            ),
            for (final o in options)
              ListTile(
                title: Text(o.name),
                subtitle: Text(
                  [
                    if (o.offeringDepartment != null) o.offeringDepartment!,
                    if (o.roomIds.isNotEmpty) o.roomIds.map(d.roomDisplay).join(', '),
                    if (o.faculty != null) o.faculty!,
                  ].join(' · '),
                ),
                trailing: o.reviewFlags.isNotEmpty ? const Icon(Icons.flag_rounded, color: CsColors.partial, size: 18) : null,
                onTap: () {
                  Navigator.pop(c);
                  _guard(context, () => s.updatePreferences({key: o.id}));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _changeDemoGroup(BuildContext context, AppState s) {
    final groups = s.data?.divisionGroups ?? const <AcademicGroup>[];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in groups)
              for (final b in g.batches)
                ListTile(
                  title: Text(g.label),
                  subtitle: Text('Batch $b'),
                  onTap: () {
                    Navigator.pop(c);
                    s.chooseDemoProfile(groupId: g.id, batch: b, name: s.profile?.displayName ?? 'Guest');
                  },
                ),
          ],
        ),
      ),
    );
  }
}
