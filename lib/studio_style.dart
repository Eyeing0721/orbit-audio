import 'package:flutter/material.dart';

/// Build either visual edition without changing project files or audio behavior.
const material3 = bool.fromEnvironment('ORBIT_M3', defaultValue: true);
const ink = Color(material3 ? 0xFF141518 : 0xFF1C1D20),
    panel = Color(material3 ? 0xFF222327 : 0xFF27282B),
    line = Color(material3 ? 0xFF43464F : 0xFF3C3E43),
    accent = Color(material3 ? 0xFFAEC6FF : 0xFF80ACD7),
    muted = Color(material3 ? 0xFFB1B6C2 : 0xFF979BA3),
    white = Color(material3 ? 0xFFE3E5EB : 0xFFD9DCE2);

ThemeData materialStudioTheme() {
  const scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: Color(0xFF102F60),
    primaryContainer: Color(0xFF304772),
    onPrimaryContainer: Color(0xFFD9E2FF),
    secondary: Color(0xFFBDC7DB),
    onSecondary: Color(0xFF273141),
    secondaryContainer: Color(0xFF364253),
    onSecondaryContainer: Color(0xFFDCE4F4),
    tertiary: Color(0xFF9CD2CA),
    onTertiary: Color(0xFF003732),
    tertiaryContainer: Color(0xFF244C47),
    onTertiaryContainer: Color(0xFFB8F0E7),
    surface: ink,
    onSurface: white,
    onSurfaceVariant: Color(0xFFC3C6D0),
    surfaceContainerLowest: Color(0xFF0F1013),
    surfaceContainerLow: Color(0xFF1B1C20),
    surfaceContainer: panel,
    surfaceContainerHigh: Color(0xFF2B2C31),
    surfaceContainerHighest: Color(0xFF35363C),
    outline: Color(0xFF8D919D),
    outlineVariant: line,
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    surfaceTint: accent,
  );
  const fontFallback = ['Microsoft YaHei UI', 'Microsoft YaHei'];
  final text = ThemeData.dark().textTheme.apply(
    bodyColor: white,
    displayColor: white,
    fontFamily: 'Segoe UI',
    fontFamilyFallback: fontFallback,
  );
  final capsule = const StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: ink,
    fontFamily: 'Segoe UI',
    fontFamilyFallback: fontFallback,
    textTheme: text,
    iconTheme: const IconThemeData(color: muted, size: 20),
    dividerTheme: const DividerThemeData(color: line, thickness: .6),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: capsule,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: fontFallback,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 40),
        side: const BorderSide(color: Color(0xFF777C87)),
        shape: capsule,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: capsule),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: capsule),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontFamily: 'Segoe UI',
            fontFamilyFallback: fontFallback,
          ),
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: line)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : muted,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.secondaryContainer,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(
        color: white,
        fontSize: 12,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: fontFallback,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: muted, fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.headlineSmall,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}
