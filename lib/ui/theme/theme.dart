import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Segue palette: soft graphite with a warm peach accent. The accent is only
/// the fallback; while music plays the UI takes its colours from the artwork.
abstract final class SegueColors {
  static const ink = Color(0xFF111114);
  static const surface = Color(0xFF1A1A1F);
  static const surfaceHigh = Color(0xFF232329);
  static const line = Color(0x1FFFFFFF);
  static const text = Color(0xFFF4F1EC);
  static const textDim = Color(0xFF9A979F);
  static const accent = Color(0xFFFF9A76);
}

/// Shared motion values so every animation feels like the same app.
abstract final class SegueMotion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 380);
  static const slow = Duration(milliseconds: 700);
  static const ease = Curves.easeOutCubic;

  /// Slight overshoot, reads as a soft spring.
  static const spring = Cubic(0.34, 1.36, 0.64, 1);
}

ThemeData buildTheme({String font = 'Manrope'}) {
  final base = ThemeData(
    useMaterial3: true,
    // Only the family name crosses the package boundary: google_fonts is
    // built on the standalone material_ui package, not flutter/material.
    fontFamily: GoogleFonts.getFont(font).fontFamily,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SegueColors.ink,
    splashFactory: InkSparkle.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: SegueColors.accent,
      secondary: SegueColors.accent,
      surface: SegueColors.surface,
      onSurface: SegueColors.text,
      onPrimary: SegueColors.ink,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
  final text = base.textTheme.apply(
    bodyColor: SegueColors.text,
    displayColor: SegueColors.text,
  );
  return base.copyWith(
    textTheme: text,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: SegueColors.surfaceHigh,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SegueColors.surfaceHigh,
      hintStyle: const TextStyle(color: SegueColors.textDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: SegueColors.line),
      ),
    ),
  );
}
