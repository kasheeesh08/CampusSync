import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/demo_repository.dart';
import '../data/firestore_repository.dart';
import '../data/local_cache.dart';
import '../data/seed_loader.dart';
import '../firebase_options.dart';
import '../services/notification_service.dart';
import 'app_state.dart';

/// Creates the [AppState] for either the Firebase backend or demo mode.
Future<AppState> bootstrap({required bool adminApp}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = await LocalCache.open();
  final notifications = NotificationService();
  if (FirebaseConfig.isConfigured) {
    await Firebase.initializeApp(options: FirebaseConfig.options);
    if (FirebaseConfig.useEmulator) {
      final host = FirebaseConfig.emulatorHost;
      // On web, a persisted session is restored against the production Auth
      // endpoint before the emulator setting applies. Test mode must never
      // contact production, so keep emulator sessions in memory only.
      if (kIsWeb) await FirebaseAuth.instance.setPersistence(Persistence.NONE);
      await FirebaseAuth.instance.useAuthEmulator(host, FirebaseConfig.authEmulatorPort);
      FirebaseFirestore.instance.useFirestoreEmulator(host, FirebaseConfig.firestoreEmulatorPort);
    }
    return AppState(
      environmentNote: FirebaseConfig.useEmulator
          ? 'Test environment: connected to the local Firebase emulator (${FirebaseConfig.emulatorProjectId} at ${FirebaseConfig.emulatorHost}:${FirebaseConfig.firestoreEmulatorPort}), not the live backend.'
          : null,
      repo: FirestoreRepository(),
      auth: AuthService(),
      cache: cache,
      notifications: notifications,
      adminApp: adminApp,
    );
  }
  return AppState(
    repo: DemoRepository(await loadBundledSeed()),
    auth: null,
    cache: cache,
    notifications: notifications,
    adminApp: adminApp,
  );
}

ThemeMode themeModeOf(String v) => switch (v) {
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => ThemeMode.light,
};
