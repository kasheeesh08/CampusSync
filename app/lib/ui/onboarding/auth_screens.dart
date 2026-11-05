import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/registration_errors.dart';
import '../../domain/models.dart';
import '../../domain/validators.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _FormScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  const _FormScaffold({required this.title, required this.subtitle, required this.children, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(actions: actions),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
              children: [
                Text(title, style: t.textTheme.headlineSmall),
                const SizedBox(height: Gap.s),
                Text(subtitle, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: Gap.xl),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().signIn(_email.text, _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final err = Validators.email(_email.text);
    if (err != null) {
      showMessage(context, 'Enter your account email above first.', error: true);
      return;
    }
    try {
      await context.read<AppState>().auth!.resetPassword(_email.text);
      if (mounted) showMessage(context, 'If an account exists for this email, a reset link has been sent.');
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: 'Welcome back',
    subtitle: 'Sign in with the email you registered with.',
    children: [
      Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            children: [
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', hintText: 'name@example.com', prefixIcon: Icon(Icons.mail_outline)),
                validator: Validators.email,
              ),
              const SizedBox(height: Gap.l),
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: Validators.signInPassword,
              ),
            ],
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: _busy ? null : _reset, child: const Text('Forgot password?')),
      ),
      const SizedBox(height: Gap.m),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Sign in'),
      ),
    ],
  );
}

/// Registration (or profile completion if the auth account already exists).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _sap = TextEditingController();
  final _roll = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _groupId;
  String? _batch;
  bool _busy = false, _obscure = true;
  late Future<List<AcademicGroup>> _groups;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _groups = s.repo.registrationGroups();
    // After email verification, restore what the student typed at sign-up.
    final d = s.registrationDraft;
    if (d != null) {
      _name.text = d.displayName;
      _sap.text = d.sapId;
      _roll.text = d.rollNumber;
      _groupId = d.requestedGroupId;
      _batch = d.batch;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _sap, _roll, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(AppState s) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await s.register(
        email: _email.text,
        password: _password.text,
        displayName: _name.text,
        sapId: _sap.text,
        rollNumber: _roll.text,
        requestedGroupId: _groupId!,
        batch: _batch,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final existing = s.user != null;
    return FutureBuilder<List<AcademicGroup>>(
      future: _groups,
      builder: (context, snap) => _buildForm(
        context,
        s,
        existing,
        snap.data ?? const [],
        snap.connectionState == ConnectionState.waiting,
        snap.connectionState == ConnectionState.waiting ? null : snap.error,
      ),
    );
  }

  /// Why the division list is empty: no connection, another failure, or the
  /// server answered but no academic groups have been set up yet.
  static String _groupsProblem(Object? error) {
    if (error == null) {
      return "Registration isn't open yet: no academic groups are configured. Please contact the CampusSync administrator.";
    }
    if (isNetworkError(error)) return 'Could not reach the server to load academic groups. Check your internet connection.';
    final code = firestoreErrorCode(error);
    return 'Academic groups could not be loaded${code == null ? '' : ' ($code)'}. Try again or contact the administrator.';
  }

  Widget _buildForm(
    BuildContext context,
    AppState s,
    bool existing,
    List<AcademicGroup> groups,
    bool loadingGroups,
    Object? groupsError,
  ) {
    final group = groups.where((g) => g.id == _groupId).firstOrNull;
    return _FormScaffold(
      // A signed-in account without a profile must still be able to leave.
      actions: [if (existing) TextButton(onPressed: s.signOut, child: const Text('Sign out'))],
      title: existing ? 'Complete your profile' : 'Create your account',
      subtitle: 'Your SAP ID and roll number identify you to the administrator. They are never used as passwords and stay private.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name *',
                  hintText: 'e.g. Priya Sharma',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: Validators.displayName,
              ),
              if (!existing) ...[
                const SizedBox(height: Gap.l),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    hintText: 'Your college or personal email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: Validators.email,
                ),
              ],
              const SizedBox(height: Gap.l),
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _sap,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: 'SAP ID *',
                  hintText: 'Digits only',
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: '',
                ),
                validator: Validators.sapId,
              ),
              const SizedBox(height: Gap.l),
              DropdownButtonFormField<String>(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                initialValue: _groupId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Academic group *', prefixIcon: Icon(Icons.groups_outlined)),
                hint: const Text('Select your division'),
                items: [
                  for (final g in groups)
                    DropdownMenuItem(
                      value: g.id,
                      child: Text(g.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _groupId = v;
                  _batch = null;
                }),
                validator: (v) => v == null ? 'Select your academic group.' : null,
              ),
              if (groups.isEmpty && !loadingGroups)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.s),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _groupsProblem(groupsError),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                      TextButton(
                        // A block body: setState must not return the Future.
                        onPressed: () => setState(() {
                          _groups = s.repo.registrationGroups();
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Gap.l),
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _roll,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Roll number *',
                  hintText: 'e.g. B001',
                  prefixIcon: Icon(Icons.tag),
                  counterText: '',
                ),
                validator: (v) => Validators.rollNumber(v, division: group?.division),
              ),
              if (group != null && group.batches.isNotEmpty) ...[
                const SizedBox(height: Gap.l),
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  initialValue: _batch,
                  decoration: const InputDecoration(labelText: 'Lab batch *', prefixIcon: Icon(Icons.science_outlined)),
                  hint: const Text('Select your lab batch'),
                  items: [for (final b in group.batches) DropdownMenuItem(value: b, child: Text('Batch $b'))],
                  onChanged: (v) => setState(() => _batch = v),
                  validator: (v) => v == null ? 'Select your lab batch.' : null,
                ),
              ],
              if (!existing) ...[
                const SizedBox(height: Gap.l),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    hintText: 'At least 8 characters, letters and numbers',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: Validators.password,
                ),
                const SizedBox(height: Gap.l),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password *',
                    hintText: 'Re-enter password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => Validators.confirmPassword(v, _password.text),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: _busy || groups.isEmpty ? null : () => _submit(s),
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(existing ? 'Submit for approval' : 'Create account'),
        ),
      ],
    );
  }
}

class AccountStatusScreen extends StatelessWidget {
  final SessionStage stage;
  const AccountStatusScreen({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final (icon, title, message) = switch (stage) {
      SessionStage.verifyEmail => (
        Icons.mark_email_unread_outlined,
        'Verify your email',
        'We sent a verification link to ${s.user?.email}. Open it, then tap "I have verified" to finish your profile.',
      ),
      SessionStage.suspended => (
        Icons.block_outlined,
        'Account suspended',
        'Your account has been suspended by the administrator. Please contact the department office.',
      ),
      _ => (
        Icons.hourglass_top_rounded,
        'Waiting for approval',
        'Thanks, ${s.profile?.displayName ?? 'there'}! An administrator will verify your SAP ID and roll number and assign your division. '
            'Your timetable unlocks once approved.',
      ),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 72, color: t.colorScheme.primary),
                  const SizedBox(height: Gap.l),
                  Text(title, style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: Gap.m),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Gap.xl),
                  if (stage == SessionStage.verifyEmail) ...[
                    FilledButton(onPressed: s.reloadUser, child: const Text('I have verified')),
                    TextButton(
                      onPressed: () async {
                        try {
                          await s.auth!.resendVerification();
                          if (context.mounted) showMessage(context, 'Verification email sent again.');
                        } catch (e) {
                          if (context.mounted) showMessage(context, e.toString(), error: true);
                        }
                      },
                      child: const Text('Resend email'),
                    ),
                  ] else if (stage == SessionStage.pendingApproval)
                    FilledButton.tonal(onPressed: s.reloadUser, child: const Text('Check status')),
                  const SizedBox(height: Gap.s),
                  TextButton(onPressed: s.signOut, child: const Text('Sign out')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
