import 'package:flutter/material.dart';

/// "Calm & trustworthy", elevated: a confident blue-teal accent, tinted-neutral
/// greys (never flat), generous spacing, soft rounded surfaces. Hand-tuned
/// light + dark to match the redesign mockups.
class PrivoiceTheme {
  static ThemeData light() => _build(_lightScheme, pageBg: const Color(0xFFEEF3F6));
  static ThemeData dark() => _build(_darkScheme, pageBg: const Color(0xFF0A1216));

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF12708D),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE0EFF4),
    onPrimaryContainer: Color(0xFF0C5C76),
    secondary: Color(0xFF12708D),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDDEEF3),
    onSecondaryContainer: Color(0xFF0C5C76),
    tertiary: Color(0xFF2F8F6B),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFDB554D),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBE7E5),
    onErrorContainer: Color(0xFF7A241F),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF0F1D24),
    onSurfaceVariant: Color(0xFF5C6E77),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F9FB),
    surfaceContainer: Color(0xFFF1F6F8),
    surfaceContainerHigh: Color(0xFFEAF1F4),
    surfaceContainerHighest: Color(0xFFE5EDF1),
    outline: Color(0xFFB6C6CE),
    outlineVariant: Color(0xFFDDE7EC),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
    inverseSurface: Color(0xFF17242B),
    onInverseSurface: Color(0xFFEAF1F4),
    inversePrimary: Color(0xFF4FB4D1),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF4FB4D1),
    onPrimary: Color(0xFF052029),
    primaryContainer: Color(0xFF13323D),
    onPrimaryContainer: Color(0xFFB6E4F1),
    secondary: Color(0xFF4FB4D1),
    onSecondary: Color(0xFF052029),
    secondaryContainer: Color(0xFF16323C),
    onSecondaryContainer: Color(0xFFB6E4F1),
    tertiary: Color(0xFF4FB98D),
    onTertiary: Color(0xFF04231A),
    error: Color(0xFFEF736B),
    onError: Color(0xFF3A0B08),
    errorContainer: Color(0xFF331F1E),
    onErrorContainer: Color(0xFFF7C9C5),
    surface: Color(0xFF111C22),
    onSurface: Color(0xFFE9F0F3),
    onSurfaceVariant: Color(0xFF93A6AF),
    surfaceContainerLowest: Color(0xFF0C161B),
    surfaceContainerLow: Color(0xFF141F26),
    surfaceContainer: Color(0xFF16232A),
    surfaceContainerHigh: Color(0xFF1B2A32),
    surfaceContainerHighest: Color(0xFF1F2F37),
    outline: Color(0xFF3A4C55),
    outlineVariant: Color(0xFF22333B),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
    inverseSurface: Color(0xFFE9F0F3),
    onInverseSurface: Color(0xFF17242B),
    inversePrimary: Color(0xFF12708D),
  );

  static ThemeData _build(ColorScheme scheme, {required Color pageBg}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pageBg,
      appBarTheme: AppBarTheme(
        backgroundColor: pageBg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
