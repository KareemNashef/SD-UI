// ==================== Glass Shader ==================== //

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Loads and caches the compiled liquid-glass fragment program.
///
/// The program is compiled once by `impellerc` at build time and loaded once
/// at runtime; every pane then gets its own cheap [ui.FragmentShader]
/// instance from it. Loading per-pane would be wasteful and, on a screen
/// with a rail + prompt bar + sheet, noticeably so.
///
/// [isSupported] is the honest gate. `ImageFilter.shader` requires Impeller,
/// which is the default renderer on Android 10+ and iOS but is not present
/// everywhere - on a Skia device the widget falls back to a plain blur
/// rather than throwing.
abstract final class GlassShader {
  static const _asset = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static bool _loadAttempted = false;
  static bool _loadFailed = false;

  /// Whether real refraction can run on this device.
  static bool get isSupported =>
      ui.ImageFilter.isShaderFilterSupported && !_loadFailed;

  /// True once [load] has completed, successfully or not.
  static bool get isReady => _loadAttempted;

  /// Whether the program is loaded and usable.
  static bool get isAvailable => _program != null && isSupported;

  /// Loads the program. Safe to call more than once; only the first call
  /// does work. Never throws - a failure just leaves the app on the
  /// fallback path.
  static Future<void> load() async {
    if (_loadAttempted) return;
    _loadAttempted = true;

    if (!ui.ImageFilter.isShaderFilterSupported) {
      _loadFailed = true;
      debugPrint('Aperture: Impeller unavailable, using fallback glass.');
      return;
    }

    try {
      _program = await ui.FragmentProgram.fromAsset(_asset);
    } catch (error) {
      _loadFailed = true;
      debugPrint('Aperture: glass shader failed to load ($error); using fallback.');
    }
  }

  /// A fresh shader instance. Callers own it and set their own uniforms.
  static ui.FragmentShader? newShader() => _program?.fragmentShader();

  /// Resets cached state. Tests only.
  @visibleForTesting
  static void resetForTesting() {
    _program = null;
    _loadAttempted = false;
    _loadFailed = false;
  }
}

/// Uniform slot layout for `shaders/liquid_glass.frag`.
///
/// Float uniforms are packed in declaration order, so these indices must
/// match the shader exactly. Naming them here means a shader edit is a
/// one-file fix rather than a hunt for magic numbers.
abstract final class GlassUniforms {
  // uniform vec2 uSize;
  static const sizeW = 0;
  static const sizeH = 1;

  // uniform vec4 uRect;  (x, y, w, h)
  static const rectX = 2;
  static const rectY = 3;
  static const rectW = 4;
  static const rectH = 5;

  // uniform vec2 uRadiusEdge;  (corner radius, edge falloff width)
  static const radius = 6;
  static const edgeWidth = 7;

  // uniform vec4 uOptics;  (refraction, dispersion, light angle, specular)
  static const refraction = 8;
  static const dispersion = 9;
  static const lightAngle = 10;
  static const specular = 11;

  // uniform vec4 uTint;  (r, g, b, amount)
  static const tintR = 12;
  static const tintG = 13;
  static const tintB = 14;
  static const tintA = 15;

  /// Total float count, for assertions.
  static const count = 16;
}
