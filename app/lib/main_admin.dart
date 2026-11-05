import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/bootstrap.dart';
import 'ui/admin/admin_shell.dart';
import 'ui/theme.dart';

/// Admin dashboard entry point (Flutter Web):
///   flutter run -d chrome -t lib/main_admin.dart
Future<void> main() async {
  final state = await bootstrap(adminApp: true);
  runApp(ChangeNotifierProvider.value(value: state..init(), child: const CampusSyncAdminApp()));
}

class CampusSyncAdminApp extends StatelessWidget {
  const CampusSyncAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CampusSync Admin',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    home: const AdminGate(),
  );
}
