// ==================== Aperture Theme ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/backend/backend_kind.dart';

// Aperture Design Tokens
//
// The whole visual system is one deliberate world: translucent "glass"
// panels over a deep, near-black ground, the backend's identity carried by
// tinting the glass itself (see [applyBackend]) rather than flooding a
// color across every border and icon. There is no light theme - the
// material only reads as glass against something dark behind it, the same
// way Apple's own Liquid Glass material is always demoed on a dark or busy
// backdrop.
//
// [accentPrimary]/[accentSecondary]/[accentTertiary] stay as mutable
// statics (same mechanism the app has used since the very first theme
// pass): every widget below reads them at build time, and [applyBackend]
// plus a keyed remount of the tree (see main_page.dart) reskins the whole
// app in one call when the active backend changes.
class AppTheme {
  AppTheme._();

  // ===== Type ===== //

  static const String fontDisplay = 'Fraunces';
  static const String fontUI = 'Manrope';

  // ===== Ink (ground) palette - fixed, backend-independent ===== //

  static const Color ink = Color(0xFF0A0A10);
  static const Color ink2 = Color(0xFF13141F);
  static const Color ink3 = Color(0xFF1B1D2E);
  static const Color ink4 = Color(0xFF242640);

  static const Color mist = Color(0xFFF3F1F7);
  static Color get mist80 => mist.withValues(alpha: 0.82);
  static Color get mist55 => mist.withValues(alpha: 0.55);
  static Color get mist35 => mist.withValues(alpha: 0.35);
  static Color get mist18 => mist.withValues(alpha: 0.18);
  static Color get mist10 => mist.withValues(alpha: 0.10);

  /// Neutral chrome accent - used for UI that belongs to the app itself
  /// (not a particular backend): the Gallery grid, Settings, generic
  /// selection states.
  static const Color moon = Color(0xFFB9C4F0);

  // ===== Fixed per-backend identity ===== //

  static const Color forgeTint = Color(0xFFFF9B57);
  static const Color forgeTint2 = Color(0xFFFFC98A);
  static const Color comfyTint = Color(0xFF9C87FF);
  static const Color comfyTint2 = Color(0xFFC7B8FF);

  // Back-compat names some call sites still use for a fixed (not
  // active-swapped) backend color, e.g. the backend picker showing both
  // identities side by side regardless of which is active.
  static const Color forgeAccentPrimary = forgeTint;
  static const Color forgeAccentSecondary = forgeTint2;
  static const Color forgeAccentTertiary = Color(0xFFFFE1BE);
  static const Color comfyAccentPrimary = comfyTint;
  static const Color comfyAccentSecondary = comfyTint2;
  static const Color comfyAccentTertiary = Color(0xFFE3DBFF);

  // ===== Active (mutable) palette ===== //

  static Color accentPrimary = forgeTint;
  static Color accentSecondary = forgeTint2;
  static Color accentTertiary = forgeAccentTertiary;
  static BackendKind _activeKind = BackendKind.forge;

  static BackendKind get activeBackendKind => _activeKind;

  /// Swaps the active tint. Call once at startup and again on every backend
  /// switch; pair with remounting the widget subtree (a keyed widget higher
  /// up) so already-built widgets pick up the new tint.
  static void applyBackend(BackendKind kind) {
    _activeKind = kind;
    if (kind == BackendKind.comfy) {
      accentPrimary = comfyTint;
      accentSecondary = comfyTint2;
      accentTertiary = comfyAccentTertiary;
    } else {
      accentPrimary = forgeTint;
      accentSecondary = forgeTint2;
      accentTertiary = forgeAccentTertiary;
    }
  }

  static Color accentFor(BackendKind kind) =>
      kind == BackendKind.comfy ? comfyTint : forgeTint;

  static Color accent2For(BackendKind kind) =>
      kind == BackendKind.comfy ? comfyTint2 : forgeTint2;

  // ===== Semantic colors ===== //
  // Deliberately distinct from both backend tints (amber/violet) so a
  // status color never reads as "the other backend".

  static const Color success = Color(0xFF3ED9A6);
  static const Color warning = Color(0xFFFFCB61);
  static const Color error = Color(0xFFFF6E85);
  static Color get info => accentPrimary;

  // ===== Glass material scale ===== //
  // Three weights, mirroring SwiftUI's own material vocabulary, mapped to
  // this app's actual jobs: thin for inline chips/badges, regular for
  // cards/toolbars, thick for sheets/modals. See GlassSurface.

  static const double glassBlurThin = 14;
  static const double glassBlurRegular = 24;
  static const double glassBlurThick = 38;

  static const double glassOpacityThin = 0.07;
  static const double glassOpacityRegular = 0.10;
  static const double glassOpacityThick = 0.14;

  // ===== Back-compat surface/border getters ===== //
  // Implemented on the new tokens so every screen not yet hand-rebuilt onto
  // GlassSurface still inherits the new palette automatically.

  static Color get glassBorder => mist18;
  static Color get glassBorderLight => mist10;
  static Color get glassBorderFocused => accentPrimary.withValues(alpha: 0.5);

  static Color get glassBackground => ink2.withValues(alpha: 0.72);
  static Color get glassBackgroundLight => ink2.withValues(alpha: 0.8);
  static Color get glassBackgroundDark => ink.withValues(alpha: 0.88);
  static Color get glassBackgroundSubtle => mist.withValues(alpha: 0.05);

  static Color get surfaceCard => ink2.withValues(alpha: 0.62);
  static Color get surfaceOverlay => ink.withValues(alpha: 0.4);
  static Color get surfaceElevated => ink3.withValues(alpha: 0.95);

  static Color get textPrimary => mist;
  static Color get textSecondary => mist80;
  static Color get textTertiary => mist55;
  static Color get textDisabled => mist35;
  static Color get textHint => mist.withValues(alpha: 0.28);

  // ===== Radius ===== //

  static const double radiusXS = 9.0;
  static const double radiusSmall = 13.0;
  static const double radiusMedium = 20.0;
  static const double radiusLarge = 28.0;
  static const double radiusXLarge = 34.0;
  static const double radiusFull = 999.0;

  // ===== Spacing ===== //

  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 12.0;
  static const double spacingLG = 16.0;
  static const double spacingXL = 24.0;
  static const double spacingXXL = 32.0;

  // ===== Typography ===== //
  // Fraunces for display moments (page/section headers), Manrope for every
  // working UI surface - inputs, buttons, body copy, labels.

  static const TextStyle display = TextStyle(
    fontFamily: fontDisplay,
    color: mist,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.05,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontDisplay,
    color: mist,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontUI,
    color: mist,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontUI,
    color: mist,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  static TextStyle get subtitleMedium => TextStyle(
    fontFamily: fontUI,
    color: mist55,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  static TextStyle get eyebrow => TextStyle(
    fontFamily: fontUI,
    color: moon,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.4,
  );

  static TextStyle get labelSmall => TextStyle(
    fontFamily: fontUI,
    color: mist80,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
  );

  static TextStyle get labelMuted => TextStyle(
    fontFamily: fontUI,
    color: mist35,
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.0,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontUI,
    color: mist,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  // ===== Shadows ===== //

  static List<BoxShadow> get shadowSmall => [
    BoxShadow(color: ink.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3)),
  ];

  static List<BoxShadow> get shadowMedium => [
    BoxShadow(color: ink.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get shadowLarge => [
    BoxShadow(color: ink.withValues(alpha: 0.55), blurRadius: 34, offset: const Offset(0, 12)),
  ];

  // ===== Modal ===== //

  static const double modalHeightFactor = 0.85;
  static const double modalBorderRadius = 32.0;

  // ===== Motion ===== //

  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 280);
  static const Duration durationSlow = Duration(milliseconds: 420);
  static const Curve ease = Curves.easeOutCubic;

  // ===== Gradients ===== //

  static LinearGradient get gradientPrimary => LinearGradient(
    colors: [accentPrimary, accentSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get gradientAction => LinearGradient(
    colors: [accentTertiary, accentPrimary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The full-page background - a deep ink wash with a very faint bloom of
  /// the active backend's tint, rather than the old solid near-black-to-
  /// tinted-black gradient. Screens layer their own ambient blobs on top of
  /// this (see AmbientField) for the glass to catch.
  static LinearGradient get gradientBackground => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ink3, ink],
  );

  static LinearGradient get gradientComfyPrimary =>
      const LinearGradient(colors: [comfyTint, comfyTint2], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static LinearGradient get gradientForgePrimary =>
      const LinearGradient(colors: [forgeTint, forgeTint2], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static LinearGradient gradientFor(BackendKind kind) =>
      kind == BackendKind.comfy ? gradientComfyPrimary : gradientForgePrimary;

  static List<BoxShadow> glowPrimary({double intensity = 0.4}) => [
    BoxShadow(color: accentPrimary.withValues(alpha: intensity), blurRadius: 26, spreadRadius: 1),
  ];

  static List<BoxShadow> glowSecondary({double intensity = 0.4}) => [
    BoxShadow(color: accentSecondary.withValues(alpha: intensity), blurRadius: 26, spreadRadius: 1),
  ];
}
