import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'app/bootstrap.dart';
import 'ui/home/home_shell.dart';
import 'ui/onboarding/auth_screens.dart';
import 'ui/onboarding/welcome_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  final state = await bootstrap(adminApp: false);
  runApp(ChangeNotifierProvider.value(value: state..init(), child: const CampusSyncApp()));
}

class CampusSyncApp extends StatelessWidget {
  const CampusSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.select((AppState s) => s.prefs);
    return MaterialApp(
      title: 'CampusSync',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeModeOf(prefs.themeMode),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(prefs.textScale)),
        child: child!,
      ),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final stage = s.stage;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: switch (stage) {
        SessionStage.loading => const Scaffold(
          key: ValueKey('loading'),
          body: Center(child: CircularProgressIndicator()),
        ),
        SessionStage.signedOut => const WelcomeScreen(key: ValueKey('welcome')),
        SessionStage.needsProfile =>
          s.isDemo ? const WelcomeScreen(key: ValueKey('welcome')) : const RegisterScreen(key: ValueKey('register')),
        SessionStage.verifyEmail ||
        SessionStage.pendingApproval ||
        SessionStage.suspended => AccountStatusScreen(key: ValueKey(stage), stage: stage),
        SessionStage.ready => const HomeShell(key: ValueKey('home')),
      },
    );
  }
}
