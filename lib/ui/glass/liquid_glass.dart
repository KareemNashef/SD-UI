// ==================== Liquid Glass ==================== //

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/glass/glass_shader.dart';
import 'package:sd_companion/ui/glass/glass_tokens.dart';

/// A pane of refractive glass.
///
/// When the device supports it, this runs `shaders/liquid_glass.frag` as an
/// `ImageFilter.shader` inside a `BackdropFilter`, so the content behind the
/// pane is physically bent at its rim, split slightly into colour at the
/// edge, and lit with a specular band that tracks the pointer. That is what
/// makes it read as glass rather than as a translucent rectangle.
///
/// When the device does not support it (no Impeller), it degrades to a plain
/// blur with the same geometry and tint. Simpler, never broken.
///
/// Cost note: refraction samples the backdrop per pixel. Use [GlassWeight.lens]
/// or [GlassWeight.prism] only for persistent chrome that exists once or
/// twice on screen. Repeating surfaces - list rows, gallery cells - must use
/// [GlassWeight.vapor], which is blur-only.
class LiquidGlass extends StatefulWidget {
  final Widget? child;
  final GlassWeight weight;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// Optional colour pulled into the glass, for engine identity.
  final Color? tint;

  /// Whether the specular highlight follows the pointer. Worth it for the
  /// handful of panes the user actually touches; pointless elsewhere.
  final bool interactive;

  const LiquidGlass({
    super.key,
    this.child,
    this.weight = GlassWeight.lens,
    this.radius = Radii.pane,
    this.padding,
    this.tint,
    this.interactive = false,
  });

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;

  /// Where the light is coming from, in radians. Default sits upper-left,
  /// matching the fixed highlight direction used across the design.
  double _lightAngle = -2.2;

  @override
  void initState() {
    super.initState();
    _shader = GlassShader.newShader();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  void _aimLightAt(Offset local, Size size) {
    if (!widget.interactive) return;
    final dx = local.dx - size.width / 2;
    final dy = local.dy - size.height / 2;
    if (dx == 0 && dy == 0) return;
    setState(() => _lightAngle = math.atan2(dy, dx));
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(widget.radius);
    final tint = widget.tint ?? Palette.chalk;

    Widget pane = LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );

        final filter = _buildFilter(size, tint);

        return ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: filter,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                // A hairline that catches light along the top edge. Even
                // with refraction doing the heavy lifting, the rim is what
                // tells the eye where the pane actually ends.
                border: Border.all(color: Palette.chalk15, width: 1),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
              ),
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        );
      },
    );

    if (!widget.interactive) return pane;

    // Bind the pane to a final local first. A closure capturing `pane`
    // directly would capture the *variable*, which is about to be reassigned
    // to the wrapper - so the builder would rebuild itself forever.
    final inner = pane;
    return Builder(
      builder: (context) => Listener(
        onPointerDown: (e) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) _aimLightAt(e.localPosition, box.size);
        },
        onPointerMove: (e) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) _aimLightAt(e.localPosition, box.size);
        },
        child: inner,
      ),
    );
  }

  /// Builds the backdrop filter: the real shader when it is available,
  /// otherwise an equivalent-geometry blur.
  ui.ImageFilter _buildFilter(Size size, Color tint) {
    final shader = _shader;
    final w = widget.weight;

    if (shader == null || !GlassShader.isAvailable || size.isEmpty) {
      return ui.ImageFilter.blur(sigmaX: w.blur, sigmaY: w.blur);
    }

    shader
      ..setFloat(GlassUniforms.sizeW, size.width)
      ..setFloat(GlassUniforms.sizeH, size.height)
      ..setFloat(GlassUniforms.rectX, 0)
      ..setFloat(GlassUniforms.rectY, 0)
      ..setFloat(GlassUniforms.rectW, size.width)
      ..setFloat(GlassUniforms.rectH, size.height)
      ..setFloat(GlassUniforms.radius, widget.radius)
      // The rim's falloff scales with the corner, so a big sheet and a small
      // chip bend light over a proportionally similar band.
      ..setFloat(GlassUniforms.edgeWidth, widget.radius * 0.9)
      ..setFloat(GlassUniforms.refraction, w.refraction)
      ..setFloat(GlassUniforms.dispersion, w.dispersion)
      ..setFloat(GlassUniforms.lightAngle, _lightAngle)
      ..setFloat(GlassUniforms.specular, 0.45)
      ..setFloat(GlassUniforms.tintR, tint.r)
      ..setFloat(GlassUniforms.tintG, tint.g)
      ..setFloat(GlassUniforms.tintB, tint.b)
      ..setFloat(GlassUniforms.tintA, w.tintAlpha);

    // The shader reads the backdrop from its sampler; composing it after a
    // blur means it refracts an already-softened image, which is what real
    // frosted-but-refractive glass looks like.
    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.shader(shader),
      inner: ui.ImageFilter.blur(sigmaX: w.blur, sigmaY: w.blur),
    );
  }
}
