import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../home/campus_world.dart';
import '../theme.dart';
import 'auth_screens.dart';
import 'demo_profile_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: Gap.l),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.school_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: Gap.m),
                        Text('CampusSync', style: t.textTheme.headlineSmall),
                      ],
                    ),
                    const SizedBox(height: Gap.xl),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: SizedBox(height: 300, child: CampusWorld(reduceMotion: s.prefs.reduceMotion)),
                    ),
                    const SizedBox(height: Gap.xl),
                    Text('Your campus, in sync.', style: t.textTheme.headlineSmall),
                    const SizedBox(height: Gap.s),
                    Text(
                      'Timetables, free classrooms, exams and announcements for MPSTME students, all in one cheerful place.',
                      style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Gap.xxl),
                    if (s.isDemo) ...[
                      FilledButton.icon(
                        icon: const Icon(Icons.explore_rounded),
                        label: const Text('Explore the demo'),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DemoProfileScreen())),
                      ),
                      const SizedBox(height: Gap.m),
                      Text(
                        'Demo mode: works offline with the bundled MPSTME timetables and campus data. No sign-in needed; nothing is saved to a server.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ] else ...[
                      FilledButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInScreen())),
                        child: const Text('Sign in'),
                      ),
                      const SizedBox(height: Gap.m),
                      OutlinedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                        child: const Text('Create student account'),
                      ),
                      const SizedBox(height: Gap.m),
                      Text(
                        'New accounts are verified by email and approved by the campus administrator before timetables unlock.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
