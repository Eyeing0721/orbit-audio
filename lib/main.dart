import 'package:flutter/material.dart';

import 'studio.dart';
import 'startup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrbitApp());
}

class OrbitApp extends StatelessWidget {
  final Widget? home;
  const OrbitApp({super.key, this.home});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ORBIT · 空间音频工作室',
    theme: material3
        ? materialStudioTheme()
        : ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: ink,
            fontFamily: 'Segoe UI',
            fontFamilyFallback: const ['Microsoft YaHei UI', 'Microsoft YaHei'],
            colorScheme: const ColorScheme.dark(
              surface: panel,
              primary: accent,
              secondary: accent,
              onPrimary: Color(0xFF17212D),
              onSurface: white,
              surfaceContainerHighest: Color(0xFF33353A),
              outline: line,
              outlineVariant: line,
              surfaceTint: Colors.transparent,
            ),
            textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: white,
              displayColor: white,
              fontFamily: 'Segoe UI',
              fontFamilyFallback: const [
                'Microsoft YaHei UI',
                'Microsoft YaHei',
              ],
            ),
            tooltipTheme: const TooltipThemeData(
              waitDuration: Duration(milliseconds: 450),
            ),
            sliderTheme: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: accent,
              inactiveTrackColor: line,
              thumbColor: accent,
            ),
            inputDecorationTheme: InputDecorationTheme(
              isDense: true,
              filled: true,
              fillColor: ink,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: line),
              ),
            ),
            dividerColor: line,
            dividerTheme: const DividerThemeData(color: line, thickness: 1),
            dialogTheme: DialogThemeData(
              backgroundColor: panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            iconTheme: const IconThemeData(size: 18, color: muted),
          ),
    home: home ?? const StartupGate(),
  );
}
