import 'package:material_ui/material_ui.dart';

const Color _ink = Color(0xFF0B0D10);
const Color _surface = Color(0xFF151A1F);
const Color _accent = Color(0xFFFFB020);

/// Dark, high-contrast theme built for one-handed use in a dim room.
///
/// Final visual design is an M3 deliverable; this is the scaffold's baseline so
/// every screen starts from the same tokens.
ThemeData buildRemoteTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: Brightness.dark,
  ).copyWith(primary: _accent, onPrimary: _ink, surface: _surface);

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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
