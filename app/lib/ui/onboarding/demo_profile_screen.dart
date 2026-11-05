import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../domain/validators.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Demo-mode profile picker: choose a supported division to preview.
class DemoProfileScreen extends StatefulWidget {
  const DemoProfileScreen({super.key});
  @override
  State<DemoProfileScreen> createState() => _DemoProfileScreenState();
}

class _DemoProfileScreenState extends State<DemoProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _groupId;
  String? _batch;
  String _avatar = 'fox';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final groups = s.data?.divisionGroups ?? const [];
    final group = groups.where((g) => g.id == _groupId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(Gap.xl),
            children: [
              Text('Pick your avatar', style: t.textTheme.titleMedium),
              const SizedBox(height: Gap.m),
              Wrap(
                spacing: Gap.m,
                runSpacing: Gap.m,
                children: [
                  for (final a in avatars.keys)
                    Semantics(
                      button: true,
                      label: 'Avatar $a',
                      selected: a == _avatar,
                      child: GestureDetector(
                        onTap: () => setState(() => _avatar = a),
                        child: AvatarBubble(a, size: 56, selected: a == _avatar),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'What should we call you?',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: Validators.displayName,
              ),
              const SizedBox(height: Gap.l),
              Text('Confirm your academic group', style: t.textTheme.titleMedium),
              const SizedBox(height: Gap.s),
              Text(
                'Only divisions with uploaded timetables are listed.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.m),
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.s),
                  child: SectionCard(
                    onTap: () => setState(() {
                      _groupId = g.id;
                      _batch = null;
                    }),
                    color: g.id == _groupId ? t.colorScheme.primaryContainer : null,
                    child: Row(
                      children: [
                        Icon(g.id == _groupId ? Icons.radio_button_checked : Icons.radio_button_off, color: t.colorScheme.primary),
                        const SizedBox(width: Gap.m),
                        Expanded(child: Text(g.label, style: t.textTheme.titleSmall)),
                      ],
                    ),
                  ),
                ),
              if (group != null && group.batches.isNotEmpty) ...[
                const SizedBox(height: Gap.m),
                Text('Lab batch', style: t.textTheme.titleMedium),
                const SizedBox(height: Gap.s),
                SegmentedButton<String>(
                  segments: [for (final b in group.batches) ButtonSegment(value: b, label: Text(b))],
                  selected: {?_batch},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (v) => setState(() => _batch = v.firstOrNull),
                ),
              ],
              const SizedBox(height: Gap.xxl),
              FilledButton(
                onPressed: () async {
                  if (!_form.currentState!.validate()) return;
                  if (_groupId == null || (group!.batches.isNotEmpty && _batch == null)) {
                    showMessage(context, 'Select your division and lab batch.', error: true);
                    return;
                  }
                  await s.chooseDemoProfile(groupId: _groupId!, batch: _batch, name: _name.text.trim());
                  await s.updatePreferences({'avatar': _avatar});
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                },
                child: const Text('Enter campus'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
