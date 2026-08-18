// ==================== Liquid Glass ==================== //

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'package:sd_companion/ui/glass/glass_tokens.dart';

/// A pane of refractive glass.
///
/// This is built on `liquid_glass_renderer`, which does the real optics:
/// per-pixel refraction through a signed-distance shape, chromatic
/// aberration, thickness-driven lensing and a moving specular highlight.
///
/// The previous hand-rolled shader here was silently failing to the plain
/// blur path, which is why all three weights looked identical - they were
/// all just `BackdropFilter(blur)` with slightly different sigmas over a
/// smooth gradient, where blur is nearly invisible.
///
/// Requires Impeller (default on Android 10+ / iOS). On anything else the
/// package's own [FakeGlass] path is used, via [GlassSurface.fake].
class GlassSurface extends StatelessWidget {
  final Widget child;
  final GlassWeight weight;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// Pulled into the glass body for engine identity.
  final Color? tint;

  /// Where the light comes from, in radians. Controls where the specular
  /// band sits; animate it to make a pane feel touched.
  final double? lightAngle;

  /// Use the cheap non-refractive path. Correct for surfaces that repeat -
  /// list rows, gallery cells - where per-pixel refraction would be paid
  /// once per item.
  final bool fake;

  const GlassSurface({
    super.key,
    required this.child,
    this.weight = GlassWeight.lens,
    this.radius = Radii.pane,
    this.padding,
    this.tint,
    this.lightAngle,
    this.fake = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = weight.settings(tint: tint, lightAngle: lightAngle);
    final shape = LiquidRoundedSuperellipse(borderRadius: radius);
    final body = padding == null ? child : Padding(padding: padding!, child: child);

    if (fake) {
      return FakeGlass(shape: shape, settings: settings, child: body);
    }

    // withOwnLayer keeps each pane self-contained. Panes that should melt
    // into one another use GlassGroup instead, which is what the package's
    // layer/blend-group machinery is actually for.
    return LiquidGlass.withOwnLayer(
      shape: shape,
      settings: settings,
      glassContainsChild: false,
      child: body,
    );
  }
}

/// Several panes sharing one glass layer.
///
/// Cheaper than one layer per pane, and shapes inside a group can blend
/// into each other the way Apple's own controls do when they get close.
/// Use this for clusters - a toolbar of buttons, a segmented control.
class GlassGroup extends StatelessWidget {
  final Widget child;
  final GlassWeight weight;
  final Color? tint;
  final double? lightAngle;

  const GlassGroup({
    super.key,
    required this.child,
    this.weight = GlassWeight.lens,
    this.tint,
    this.lightAngle,
  });

  @override
  Widget build(BuildContext context) => LiquidGlassLayer(
        settings: weight.settings(tint: tint, lightAngle: lightAngle),
        child: child,
      );
}

/// One pane inside a [GlassGroup].
class GlassPane extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  const GlassPane({
    super.key,
    required this.child,
    this.radius = Radii.pane,
    this.padding,
  });

  @override
  Widget build(BuildContext context) => LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      );
}
