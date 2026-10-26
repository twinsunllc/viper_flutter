// The widget's tokens (widget/src/loader/ui/styles.ts, widget/src/panel/styles.ts, W01, W14), so
// what Viper draws in Flutter looks like what it draws on the web.
import 'package:flutter/widgets.dart';

/// Ink, the launcher and the panel's header in both themes.
const Color viperInk = Color(0xFF15171C);

/// The lime signal in the launcher's eye.
const Color viperSignal = Color(0xFFC6F432);

/// The needs-you dot.
const Color viperNeeds = Color(0xFFE0520F);

/// The colors that change with the theme (D279).
@immutable
class ViperPalette {
  /// A palette.
  const ViperPalette({
    required this.dark,
    required this.surface,
    required this.bar,
    required this.line,
    required this.skeleton,
    required this.skeletonHighlight,
    required this.halo,
    required this.shadow,
    required this.countBackground,
    required this.text,
    required this.subtle,
  });

  /// Whether this is the dark theme.
  final bool dark;

  /// The sheet behind the panel.
  final Color surface;

  /// The panel's header bar.
  final Color bar;

  /// Borders.
  final Color line;

  /// Skeleton blocks and their shimmer.
  final Color skeleton;

  /// The shimmer's light band.
  final Color skeletonHighlight;

  /// The ring that sets the launcher apart from the app.
  final Color halo;

  /// The launcher's shadow.
  final Color shadow;

  /// The open count's background.
  final Color countBackground;

  /// Text on the surface.
  final Color text;

  /// Secondary text.
  final Color subtle;

  /// The light theme.
  static const ViperPalette light = ViperPalette(
    dark: false,
    surface: Color(0xFFFFFFFF),
    bar: viperInk,
    line: Color(0xFFE3E6EA),
    skeleton: Color(0xFFECEEF1),
    skeletonHighlight: Color(0xFFF7F8F9),
    halo: Color(0xE6FFFFFF),
    shadow: Color(0x5215171C),
    countBackground: Color(0xFFFFFFFF),
    text: viperInk,
    subtle: Color(0xFF5B616B),
  );

  /// The dark theme (W14).
  static const ViperPalette darkTheme = ViperPalette(
    dark: true,
    surface: Color(0xFF171A1F),
    bar: Color(0xFF0A0B0D),
    line: Color(0xFF2A2F37),
    skeleton: Color(0xFF22262D),
    skeletonHighlight: Color(0xFF2E333B),
    halo: Color(0xF25A606A),
    shadow: Color(0x80000000),
    countBackground: Color(0xFFECEEF0),
    text: Color(0xFFECEEF0),
    subtle: Color(0xFFB4BAC3),
  );

  /// The palette for a theme choice, `system` following the phone.
  static ViperPalette of(String theme, Brightness platform) {
    if (theme == 'dark') return darkTheme;
    if (theme == 'light') return light;
    return platform == Brightness.dark ? darkTheme : light;
  }
}
