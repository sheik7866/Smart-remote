import 'package:material_ui/material_ui.dart';

const Color _ink = Color(0xFF0B0D10);
const Color _surface = Color(0xFF151A1F);
const Color _raised = Color(0xFF1C232A);
const Color _accent = Color(0xFFFFB020);
const Color _good = Color(0xFF4ADE80);
const Color _warn = Color(0xFFFBBF24);
const Color _bad = Color(0xFFF87171);

/// Semantic colours for connection state, so every screen agrees on what
/// "connected" and "degraded" look like.
abstract final class RemoteColors {
  static const Color ink = _ink;
  static const Color surface = _surface;
  static const Color raised = _raised;
  static const Color accent = _accent;
  static const Color good = _good;
  static const Color warning = _warn;
  static const Color danger = _bad;
}

/// Dark, high-contrast theme built for one-handed use in a dim room.
ThemeData buildRemoteTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: _accent,
        onPrimary: _ink,
        surface: _surface,
        surfaceContainerHighest: _raised,
        error: _bad,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _ink,
    appBarTheme: const AppBarTheme(
      backgroundColor: _ink,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: _surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF2A333C)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: _accent,
      inactiveTrackColor: const Color(0xFF2A333C),
      thumbColor: _accent,
      overlayColor: _accent.withValues(alpha: 0.16),
      trackHeight: 6,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2A333C)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2A333C)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _raised,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
