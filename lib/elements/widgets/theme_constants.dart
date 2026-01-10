// ==================== Theme Constants ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Theme Constants Implementation

/// Design system constants following the glassmorphism theme
/// Uses accentPrimary (cyan) and accentSecondary (purple) as the main accent colors
class AppTheme {
  // ===== Class Variables ===== //

  // Primary Accent Colors
  static const Color accentPrimary = Color(0xFF15803D);
  static const Color accentSecondary = Color(0xFF65A30D);
  static const Color accentTertiary = Color(0xFFBBF7D0);

  // Semantic Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE53935);
  static const Color info = accentPrimary;

  // Glass Surface Colors
  static Color get glassBorder => Colors.white.withValues(alpha: 0.15);
  static Color get glassBorderLight => Colors.white.withValues(alpha: 0.08);
  static Color get glassBorderFocused => accentPrimary.withValues(alpha: 0.5);

  static Color get glassBackground =>
      const Color(0xFF121212).withValues(alpha: 0.7);
  static Color get glassBackgroundLight =>
      const Color(0xFF121212).withValues(alpha: 0.75);
  static Color get glassBackgroundDark =>
      const Color(0xFF0A0A0A).withValues(alpha: 0.85);
  static Color get glassBackgroundSubtle =>
      Colors.white.withValues(alpha: 0.05);

  // Surface Colors
  static Color get surfaceCard => Colors.grey.shade900.withValues(alpha: 0.6);
  static Color get surfaceOverlay => Colors.black.withValues(alpha: 0.3);
  static Color get surfaceElevated =>
      const Color(0xFF1E1E1E).withValues(alpha: 0.95);

  // Text Colors
  static Color get textPrimary => Colors.white;
  static Color get textSecondary => Colors.white.withValues(alpha: 0.7);
  static Color get textTertiary => Colors.white.withValues(alpha: 0.5);
  static Color get textDisabled => Colors.white.withValues(alpha: 0.3);
  static Color get textHint => Colors.white.withValues(alpha: 0.25);

  // Border Radius
  static const double radiusXS = 6.0;
  static const double radiusSmall = 12.0;
  static const double radiusMedium = 20.0;
  static const double radiusLarge = 24.0;
  static const double radiusXLarge = 28.0;
  static const double radiusFull = 50.0;

  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 12.0;
  static const double spacingLG = 16.0;
  static const double spacingXL = 24.0;
  static const double spacingXXL = 32.0;

  // Typography
  static const TextStyle titleLarge = TextStyle(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  static const TextStyle titleMedium = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  static const TextStyle titleSmall = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get subtitleMedium => TextStyle(
    color: Colors.white.withValues(alpha: 0.5),
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get labelSmall => TextStyle(
    color: Colors.white.withValues(alpha: 0.7),
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static TextStyle get labelMuted => TextStyle(
    color: Colors.white.withValues(alpha: 0.4),
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.0,
  );

  static const TextStyle bodyMedium = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  // Shadows
  static List<BoxShadow> get shadowSmall => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMedium => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLarge => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  // Modal
  static const double modalHeightFactor = 0.85;
  static const double modalBorderRadius = 28.0;

  // Animation Durations
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);

  // Gradients
  static LinearGradient get gradientPrimary => const LinearGradient(
    colors: [accentPrimary, accentSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get gradientAction => const LinearGradient(
    colors: [accentTertiary, accentPrimary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get gradientBackground => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.black, Colors.grey.shade900],
  );

  // ===== Class Methods ===== //

  static List<BoxShadow> glowPrimary({double intensity = 0.4}) => [
    BoxShadow(
      color: accentPrimary.withValues(alpha: intensity),
      blurRadius: 12,
      spreadRadius: 1,
    ),
  ];

  static List<BoxShadow> glowSecondary({double intensity = 0.4}) => [
    BoxShadow(
      color: accentSecondary.withValues(alpha: intensity),
      blurRadius: 12,
      spreadRadius: 1,
    ),
  ];
}
