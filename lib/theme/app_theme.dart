import 'package:flutter/material.dart';

/// The Nearlink palette, lifted from the original prototype so the Flutter app
/// and the web mock share one visual language.
class NearlinkColors {
  NearlinkColors._();

  static const Color ink = Color(0xFF19231D);
  static const Color muted = Color(0xFF6B736D);
  static const Color line = Color(0xFFDFE3DF);
  static const Color canvas = Color(0xFFF5F7F4);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color soft = Color(0xFFEEF2EE);

  static const Color accent = Color(0xFF006C4E);
  static const Color accentDeep = Color(0xFF004D38);
  static const Color lime = Color(0xFFC8F14A);
  static const Color orange = Color(0xFFFFB359);

  static const Color sidebar = Color(0xFF183B30);
  static const Color sidebarInk = Color(0xFFBFD0C8);

  static const Color online = Color(0xFF4B9B43);
  static const Color danger = Color(0xFFC14A40);
  static const Color dangerSoft = Color(0xFFFFF1F0);

  static const Color heroBg = Color(0xFFE5F0D9);
  static const Color heroInk = Color(0xFF51634F);
}

class NearlinkTheme {
  NearlinkTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: NearlinkColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: NearlinkColors.accent,
      onPrimary: Colors.white,
      secondary: NearlinkColors.lime,
      surface: NearlinkColors.panel,
      onSurface: NearlinkColors.ink,
      error: NearlinkColors.danger,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: NearlinkColors.canvas,
      dividerColor: NearlinkColors.line,
      textTheme: base.textTheme.apply(
        bodyColor: NearlinkColors.ink,
        displayColor: NearlinkColors.ink,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NearlinkColors.sidebar,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NearlinkColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NearlinkColors.ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: NearlinkColors.line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NearlinkColors.accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? NearlinkColors.accent
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? NearlinkColors.accent.withValues(alpha: 0.35)
              : NearlinkColors.line,
        ),
      ),
    );
  }

  /// Heading style with the prototype's tight tracking.
  static TextStyle heading(BuildContext context, {double size = 32}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -size * 0.045,
        height: 1.05,
        color: NearlinkColors.ink,
      );
}
