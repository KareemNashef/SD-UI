// ==================== Glass Tokens ==================== //

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'package:sd_companion/domain/engine/engine_kind.dart';

/// The design tokens from DESIGN.md, as code.
///
/// Everything is `const` and nothing is mutable. The previous theme swapped
/// mutable statics on engine change and then remounted the whole widget tree
/// to make the change take - engine tint is now passed down explicitly
/// instead, so nothing has to be remounted and no widget can read a stale
/// colour.
abstract final class Palette {
  static const void_ = Color(0xFF06060A);
  static const well = Color(0xFF0E0F16);
  static const deep = Color(0xFF14161F);

  static const chalk = Color(0xFFF2F3F7);
  static const chalk70 = Color(0xB3F2F3F7);
  static const chalk40 = Color(0x66F2F3F7);
  static const chalk15 = Color(0x26F2F3F7);
  static const chalk08 = Color(0x14F2F3F7);

  /// Engine identity. Used in exactly three places: the status dot, the
  /// active selection ring, and the aperture button.
  static const ember = Color(0xFFFF8A4C); // Forge Neo
  static const iris = Color(0xFF8B7CFF); // ComfyUI

  static const alert = Color(0xFFFF5C7A);
  static const caution = Color(0xFFFFC24B);

  static Color tintFor(EngineKind kind) =>
      kind == EngineKind.comfy ? iris : ember;
}

/// Corner radii. Generous, because the corner is what the refraction reads
/// along - a tight radius leaves the lens nothing to bend.
abstract final class Radii {
  static const pane = 28.0;
  static const sheet = 32.0;
  static const well = 14.0;
  static const pill = 999.0;
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Motion {
  static const press = Duration(milliseconds: 120);
  static const pane = Duration(milliseconds: 260);
  static const sheet = Duration(milliseconds: 380);
  static const stage = Duration(milliseconds: 450);

  static const ease = Curves.easeOutCubic;
  static const rise = Curves.easeOutQuint;
}

/// Type roles. Geist for UI, Geist Mono for every numeral the app shows -
/// tabular figures keep parameter columns aligned and stop live counters
/// jittering as they tick.
abstract final class Type {
  static const _ui = 'Geist';
  static const _mono = 'GeistMono';

  static const stageTitle = TextStyle(
      fontFamily: _ui, fontSize: 28, fontWeight: FontWeight.w700, color: Palette.chalk, height: 1.15);
  static const sheetTitle = TextStyle(
      fontFamily: _ui, fontSize: 20, fontWeight: FontWeight.w700, color: Palette.chalk);
  static const body = TextStyle(
      fontFamily: _ui, fontSize: 15, fontWeight: FontWeight.w400, color: Palette.chalk, height: 1.45);
  static const label = TextStyle(
      fontFamily: _ui, fontSize: 13, fontWeight: FontWeight.w600, color: Palette.chalk);
  static const micro = TextStyle(
      fontFamily: _ui,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: Palette.chalk40);

  static const readout = TextStyle(
      fontFamily: _mono,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Palette.chalk70,
      fontFeatures: [FontFeature.tabularFigures()]);
  static const readoutLarge = TextStyle(
      fontFamily: _mono,
      fontSize: 32,
      fontWeight: FontWeight.w500,
      color: Palette.chalk,
      fontFeatures: [FontFeature.tabularFigures()]);
}

/// The three weights of the material.
///
/// The numbers are chosen so the weights are *obviously* different at a
/// glance, which the previous set were not. `thickness` is the dominant
/// term - it drives how much the glass lenses what is behind it - so it
/// roughly triples across the scale rather than nudging.
enum GlassWeight {
  /// Thin and barely refractive. Chips, badges, and anything that repeats.
  vapor(
    thickness: 8,
    blur: 2,
    refractiveIndex: 1.15,
    chromaticAberration: 0.0,
    lightIntensity: 0.5,
    saturation: 1.1,
    glassAlpha: 0.10,
  ),

  /// Clearly lensed, with a visible specular edge. The persistent chrome:
  /// rail, prompt bar, filmstrip, controls.
  lens(
    thickness: 22,
    blur: 4,
    refractiveIndex: 1.35,
    chromaticAberration: 0.04,
    lightIntensity: 1.0,
    saturation: 1.4,
    glassAlpha: 0.06,
  ),

  /// Heavy, deeply lensed, with obvious colour fringing at the rim.
  /// Sheets and dialogs only, one at a time.
  prism(
    thickness: 44,
    blur: 8,
    refractiveIndex: 1.55,
    chromaticAberration: 0.10,
    lightIntensity: 1.4,
    saturation: 1.7,
    glassAlpha: 0.04,
  );

  /// How deep the slab is. The main lever on how much the backdrop bends.
  final double thickness;

  /// Frosting behind the refraction. Kept low - heavy blur destroys the
  /// detail that makes refraction legible in the first place.
  final double blur;

  /// 1.0 is no bending; ~1.5 is realistic glass.
  final double refractiveIndex;

  /// Colour fringing at the rim.
  final double chromaticAberration;

  final double lightIntensity;
  final double saturation;

  /// Opacity of the pane's own body tint.
  final double glassAlpha;

  const GlassWeight({
    required this.thickness,
    required this.blur,
    required this.refractiveIndex,
    required this.chromaticAberration,
    required this.lightIntensity,
    required this.saturation,
    required this.glassAlpha,
  });

  /// Default light direction: upper-left, matching the highlight direction
  /// used consistently across the design.
  static const defaultLightAngle = -0.7 * math.pi;

  LiquidGlassSettings settings({Color? tint, double? lightAngle}) =>
      LiquidGlassSettings(
        thickness: thickness,
        blur: blur,
        refractiveIndex: refractiveIndex,
        chromaticAberration: chromaticAberration,
        lightAngle: lightAngle ?? defaultLightAngle,
        lightIntensity: lightIntensity,
        saturation: saturation,
        glassColor: (tint ?? Palette.chalk).withValues(alpha: glassAlpha),
      );
}
