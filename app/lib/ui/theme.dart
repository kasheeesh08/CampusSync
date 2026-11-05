import 'package:flutter/material.dart';

import '../domain/availability.dart';

/// CampusSync visual identity: a bright, cosy campus palette.
class CsColors {
  static const seed = Color(0xFF5B6CFF); // campus blue
  static const sky = Color(0xFFDDE7FF);
  static const skyDeep = Color(0xFFB9CBFF);
  static const grass = Color(0xFF8BD8A6);
  static const grassDeep = Color(0xFF5CBF85);
  static const sun = Color(0xFFFFC857);
  static const coral = Color(0xFFFF8A65);
  static const mint = Color(0xFF3CC9A0);
  static const lilac = Color(0xFFB79CFF);
  static const brick = Color(0xFFF4A27A);
  static const cream = Color(0xFFF8F7FF);

  static const occupied = Color(0xFFE5484D);
  static const free = Color(0xFF2FB67C);
  static const partial = Color(0xFFF5A524);
  static const unavailable = Color(0xFF8E8EA0);

  static Color forStatus(RoomStatus s) => switch (s) {
    RoomStatus.occupied => occupied,
    RoomStatus.freeVerified => free,
    RoomStatus.noKnownClass => partial,
    RoomStatus.unavailable || RoomStatus.unknownRoom => unavailable,
  };

  static String statusLabel(RoomStatus s) => switch (s) {
    RoomStatus.occupied => 'Occupied',
    RoomStatus.freeVerified => 'Free (verified schedule)',
    RoomStatus.noKnownClass => 'No class listed · unverified',
    RoomStatus.unavailable => 'Unavailable',
    RoomStatus.unknownRoom => 'Unknown room',
  };

  static const subjectPalette = [
    Color(0xFF5B6CFF),
    Color(0xFF3CC9A0),
    Color(0xFFFF8A65),
    Color(0xFFB079F2),
    Color(0xFFF5A524),
    Color(0xFF2BA8D8),
    Color(0xFFE5679A),
    Color(0xFF7FB547),
  ];

  static Color forSubject(String? code) =>
      code == null ? unavailable : subjectPalette[code.codeUnits.fold<int>(0, (a, b) => a + b) % subjectPalette.length];
}

class Gap {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: CsColors.seed, brightness: brightness);
  final light = brightness == Brightness.light;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: light ? CsColors.cream : scheme.surface,
    textTheme: base.textTheme
        .apply(fontFamilyFallback: const ['Roboto'])
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? Colors.white : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light ? Colors.white : scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
