/// Noctorium's Night theme, as Material 3 needs it.
///
/// The six colours are Night's own, the ones the player and the desktop draw with, rather than a palette
/// Material works out from a seed: this should read as part of Noctorium, not as a phone app that happens to
/// share its name. The rest of the scheme is mixed from those six with the same sums the player uses.
library;

import 'package:flutter/material.dart';

abstract final class Night {
  static const page = Color(0xFF000000);
  static const panel = Color(0xFF07050A);
  static const card = Color(0xFF15101C);
  static const text = Color(0xFFF8F4FF);
  static const subtext = Color(0xFFCFC5DA);
  static const accent = Color(0xFFB47CFF);

  /// A card a step up from a card: a selected chip, a field being typed in.
  static final raised = Color.lerp(card, text, .06)!;

  /// Lines and the quiet parts of a chart: grid lines, an empty bar's track.
  static final line = Color.lerp(subtext, page, .78)!;

  /// Text that matters less than the subtext: axis labels, ranks.
  static final faint = Color.lerp(subtext, page, .38)!;

  static const error = Color(0xFFFF8A8A);
}

/// Writing on the accent: the violet is light enough that white on it is hard to read, so it is a violet so
/// dark it is nearly black.
const onAccent = Color(0xFF1A0B2E);

ThemeData nightTheme() {
  final scheme = const ColorScheme.dark().copyWith(
    primary: Night.accent,
    onPrimary: onAccent,
    primaryContainer: Color.lerp(Night.accent, Night.page, .74),
    onPrimaryContainer: Color.lerp(Night.accent, Night.text, .55),
    secondary: Color.lerp(Night.accent, Night.text, .38),
    onSecondary: Night.page,
    secondaryContainer: Color.lerp(Night.accent, Night.page, .82),
    onSecondaryContainer: Night.text,
    tertiary: Color.lerp(Night.accent, Night.subtext, .5),
    surface: Night.panel,
    onSurface: Night.text,
    onSurfaceVariant: Night.subtext,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Night.page,
    surfaceContainerLow: Color.lerp(Night.panel, Night.page, .5),
    surfaceContainer: Night.panel,
    surfaceContainerHigh: Night.card,
    surfaceContainerHighest: Night.raised,
    surfaceBright: Night.card,
    surfaceDim: Night.page,
    inverseSurface: Night.text,
    onInverseSurface: Night.page,
    error: Night.error,
    onError: const Color(0xFF2A0008),
    errorContainer: const Color(0xFF3D0713),
    onErrorContainer: const Color(0xFFFFDAD6),
    outline: Color.lerp(Night.subtext, Night.page, .45),
    outlineVariant: Night.line,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  final text = base.textTheme.apply(bodyColor: Night.text, displayColor: Night.text);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return base.copyWith(
    scaffoldBackgroundColor: Night.page,
    canvasColor: Night.page,
    textTheme: text.copyWith(
      bodyMedium: text.bodyMedium?.copyWith(color: Night.subtext, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(color: Night.subtext, height: 1.35),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(color: Night.faint, letterSpacing: .2),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Night.page,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Night.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Night.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Night.card,
      selectedColor: Night.accent,
      labelStyle: text.labelLarge?.copyWith(color: Night.subtext, fontWeight: FontWeight.w600),
      secondaryLabelStyle: text.labelLarge?.copyWith(color: onAccent, fontWeight: FontWeight.w700),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Night.accent,
        foregroundColor: onAccent,
        minimumSize: const Size(64, 52),
        shape: rounded,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Night.text,
        side: BorderSide(color: Night.line),
        minimumSize: const Size(64, 48),
        shape: rounded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Night.accent, shape: rounded),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Night.card,
      labelStyle: const TextStyle(color: Night.subtext),
      floatingLabelStyle: const TextStyle(color: Night.accent),
      hintStyle: TextStyle(color: Night.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Night.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Night.error, width: 1.2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Night.card,
        foregroundColor: Night.subtext,
        selectedBackgroundColor: Night.accent,
        selectedForegroundColor: onAccent,
        side: BorderSide.none,
        minimumSize: const Size(0, 48),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Night.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: text.bodyLarge?.copyWith(color: Night.text),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Night.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Night.raised,
      contentTextStyle: text.bodyMedium?.copyWith(color: Night.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Night.accent),
    dividerTheme: DividerThemeData(color: Night.line, thickness: 1, space: 1),
  );
}
