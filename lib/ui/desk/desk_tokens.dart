// ==================== Desk Tokens ==================== //
//
// The whole design system's constants, in one place. See DESIGN.md.
//
// The governing constraint: everything here renders with flat fills, solid
// strokes and transforms. No shader, no backdrop filter, no blurred shadow
// appears anywhere in this file or anything built on it - which is what makes
// the look cheap enough to animate freely.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Day / night. A desk lamp turned down, not an inversion: paper stays
/// lighter than the desk and ink stays the darkest thing on screen.
enum DeskMode { day, night }

@immutable
class DeskPalette {
  final Color desk;
  final Color deskGrain;
  final Color paper;
  final Color paperEdge;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color clay;
  final Color clayDeep;

  const DeskPalette({
    required this.desk,
    required this.deskGrain,
    required this.paper,
    required this.paperEdge,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.clay,
    required this.clayDeep,
  });

  static const day = DeskPalette(
    desk: Color(0xFFDED2BC),
    deskGrain: Color(0x07000000),
    paper: Color(0xFFFBF7EF),
    paperEdge: Color(0xFFEFE8D9),
    ink: Color(0xFF211C14),
    inkMuted: Color(0xFF4C4536),
    inkFaint: Color(0xFF7A7364),
    clay: Color(0xFFC4472F),
    clayDeep: Color(0xFFA9331E),
  );

  static const night = DeskPalette(
    desk: Color(0xFF2A241B),
    deskGrain: Color(0x0D000000),
    paper: Color(0xFFE4DAC4),
    paperEdge: Color(0xFFD5CAB2),
    ink: Color(0xFF14110C),
    inkMuted: Color(0xFF3E382C),
    inkFaint: Color(0xFF6A6252),
    clay: Color(0xFFD4573C),
    clayDeep: Color(0xFFB03B22),
  );

  static DeskPalette of(DeskMode mode) =>
      mode == DeskMode.day ? day : night;

  // Semantic. Used for meaning only, never decoration - and always as a
  // stamp (text + border, no fill) so they never compete with clay.
  static const good = Color(0xFF4A7A46);
  static const caution = Color(0xFFC98A1E);
  static const alert = Color(0xFFA32B1C);
}

/// The active palette, handed down the tree. Defaults to day so a widget
/// built outside a [DeskTheme] still renders correctly.
class DeskTheme extends InheritedWidget {
  final DeskPalette palette;
  final DeskMode mode;

  const DeskTheme({
    super.key,
    required this.palette,
    required this.mode,
    required super.child,
  });

  static DeskPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeskTheme>()?.palette ??
      DeskPalette.day;

  static DeskMode modeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeskTheme>()?.mode ??
      DeskMode.day;

  @override
  bool updateShouldNotify(DeskTheme old) => old.palette != palette;
}

// ===== Space ===== //

/// `4 · 8 · 12 · 16 · 24 · 32 · 48`. Nothing between these values.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 48.0;

  /// Screen gutter, and the width the tool tray occupies on the left.
  static const gutter = 12.0;
  static const trayWidth = 44.0;

  /// Minimum touch target on every side.
  static const touch = 44.0;
}

// ===== Corners ===== //

/// Paper as content is square; controls are rounded. This is the rule that
/// lets you tell content from control without reading a word - so there is
/// deliberately no "pill" value here. Aperture has no pill shapes.
abstract final class Corner {
  static const paper = 0.0;
  static const photo = 2.0;
  static const control = 10.0;
  static const panel = 12.0;
  static const trayOuter = 16.0;
}

// ===== Borders ===== //

abstract final class Stroke {
  static const hairline = 1.0;
  static const standard = 2.0;
  static const live = 2.5;
  static const frame = 3.0;
}

// ===== Depth ===== //

/// A solid offset in ink at zero blur, always down-right at a 3:4 ratio.
///
/// The offset is what encodes height, so it is only ever animated to a
/// smaller or larger magnitude along the same diagonal - never to a
/// different direction.
@immutable
class Elevation {
  final Offset offset;
  final double opacity;

  const Elevation(this.offset, this.opacity);

  static const none = Elevation(Offset.zero, 0);
  static const rest = Elevation(Offset(2, 3), 0.22);
  static const raised = Elevation(Offset(3, 4), 0.22);
  static const sheet = Elevation(Offset(4, 6), 0.22);
  static const lifted = Elevation(Offset(6, 8), 0.26);

  /// Modals rise from the bottom edge, so their shadow points up.
  static const drawer = Elevation(Offset(0, -6), 0.28);

  /// What an object looks like while pressed: sunk into its own shadow.
  static const pressed = Elevation(Offset(1, 1), 0.18);

  List<BoxShadow> shadows(Color ink) => opacity == 0
      ? const []
      : [
          BoxShadow(
            color: ink.withValues(alpha: opacity),
            offset: offset,
            blurRadius: 0,
          ),
        ];

  static Elevation lerp(Elevation a, Elevation b, double t) => Elevation(
        Offset.lerp(a.offset, b.offset, t)!,
        a.opacity + (b.opacity - a.opacity) * t,
      );
}

// ===== Motion ===== //

abstract final class Motion {
  // Springs, described the way SpringDescription wants them.
  static const pressSpring =
      SpringDescription(mass: 1, stiffness: 420, damping: 26);
  static const settleSpring =
      SpringDescription(mass: 1, stiffness: 300, damping: 22);
  static const snapSpring =
      SpringDescription(mass: 1, stiffness: 520, damping: 30);
  static const driftSpring =
      SpringDescription(mass: 1, stiffness: 140, damping: 18);

  // Durations, where a spring is not appropriate.
  static const press = Duration(milliseconds: 90);
  static const fade = Duration(milliseconds: 220);
  static const drawer = Duration(milliseconds: 320);
  static const arrival = Duration(milliseconds: 420);

  /// Stagger between prints in one batch.
  static const stagger = Duration(milliseconds: 80);

  /// Handle pulse period. The only permanently animating element.
  static const pulse = Duration(milliseconds: 4400);

  static const settle = Curves.easeOutBack;
  static const ease = Curves.easeOutCubic;
  static const snap = Curves.easeOutQuart;
}

// ===== Type ===== //

abstract final class Type {
  static const _ui = 'Geist';
  static const _mono = 'GeistMono';

  static const deskTitle = TextStyle(
    fontFamily: _ui, fontSize: 24, fontWeight: FontWeight.w700,
    letterSpacing: -0.84, height: 1.1,
  );

  static const sheetTitle = TextStyle(
    fontFamily: _ui, fontSize: 19, fontWeight: FontWeight.w700,
    letterSpacing: -0.48, height: 1.15,
  );

  static const body = TextStyle(
    fontFamily: _ui, fontSize: 13.5, fontWeight: FontWeight.w400, height: 1.45,
  );

  static const label = TextStyle(
    fontFamily: _ui, fontSize: 12, fontWeight: FontWeight.w600,
    letterSpacing: -0.12, height: 1.2,
  );

  static const value = TextStyle(
    fontFamily: _ui, fontSize: 20, fontWeight: FontWeight.w700,
    letterSpacing: -0.6, height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// UPPERCASE only, and always the label printed on a physical thing.
  static const micro = TextStyle(
    fontFamily: _mono, fontSize: 8.5, fontWeight: FontWeight.w400,
    letterSpacing: 1.36, height: 1.3,
  );

  /// Anything a machine produced. Tabular so it cannot reflow while updating.
  static const readout = TextStyle(
    fontFamily: _mono, fontSize: 12, fontWeight: FontWeight.w500,
    letterSpacing: 0.24, height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

// ===== Deterministic rotation ===== //

/// A print's resting angle, in radians, derived from its image id.
///
/// Deriving it from a stable input rather than `Random()` is what stops a
/// print jittering every time the list rebuilds - the single most common way
/// this kind of design goes wrong.
double restAngleFor(String id) {
  final bucket = id.hashCode.abs() % 9; // 0..8
  return (bucket - 4) * 0.9 * math.pi / 180; // -3.6deg .. +3.6deg
}

/// Whether the OS has asked for reduced motion. Layout must never depend on
/// an animation having run, so this only ever removes movement.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
