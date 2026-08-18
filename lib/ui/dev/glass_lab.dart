// ==================== Glass Lab ==================== //

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/glass/glass_shader.dart';
import 'package:sd_companion/ui/glass/glass_tokens.dart';
import 'package:sd_companion/ui/glass/liquid_glass.dart';

/// Puts every weight of the material on screen at once, over live moving
/// colour, so the refraction can be judged on real hardware rather than
/// inferred from a screenshot.
///
/// What to look for:
///  * the background should *bend* at each pane's rim and stay straight
///    through its middle - that edge-only distortion is the whole point;
///  * a faint colour fringe at the rim on Prism (chromatic dispersion);
///  * the highlight on the interactive pane should follow your finger.
class GlassLab extends StatelessWidget {
  const GlassLab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        const _Note(),
        const SizedBox(height: Space.lg),

        _Sample(
          title: 'Vapor',
          note: 'Blur only. Safe to repeat in lists.',
          child: LiquidGlass(
            weight: GlassWeight.vapor,
            radius: Radii.well,
            padding: const EdgeInsets.all(Space.lg),
            child: _Filler(label: 'vapor'),
          ),
        ),

        _Sample(
          title: 'Lens',
          note: 'Blur + edge refraction + specular. The persistent chrome.',
          child: LiquidGlass(
            weight: GlassWeight.lens,
            radius: Radii.pane,
            padding: const EdgeInsets.all(Space.lg),
            child: _Filler(label: 'lens'),
          ),
        ),

        _Sample(
          title: 'Prism',
          note: 'Adds chromatic dispersion. Sheets only, one at a time.',
          child: LiquidGlass(
            weight: GlassWeight.prism,
            radius: Radii.sheet,
            padding: const EdgeInsets.all(Space.lg),
            child: _Filler(label: 'prism'),
          ),
        ),

        _Sample(
          title: 'Interactive',
          note: 'Press and drag - the specular highlight tracks your finger.',
          child: LiquidGlass(
            weight: GlassWeight.prism,
            radius: Radii.sheet,
            interactive: true,
            padding: const EdgeInsets.all(Space.xl),
            child: SizedBox(
              height: 90,
              child: Center(
                child: Text('touch me', style: Type.body),
              ),
            ),
          ),
        ),

        _Sample(
          title: 'Engine tint',
          note: 'Identity enters through the glass, not as a flat accent.',
          child: Row(
            children: [
              Expanded(
                child: LiquidGlass(
                  weight: GlassWeight.lens,
                  radius: Radii.pane,
                  tint: Palette.ember,
                  padding: const EdgeInsets.all(Space.lg),
                  child: _Filler(label: 'Forge', color: Palette.ember),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: LiquidGlass(
                  weight: GlassWeight.lens,
                  radius: Radii.pane,
                  tint: Palette.iris,
                  padding: const EdgeInsets.all(Space.lg),
                  child: _Filler(label: 'Comfy', color: Palette.iris),
                ),
              ),
            ],
          ),
        ),

        _Sample(
          title: 'Mono numerals',
          note: 'Tabular figures - these columns must not shift as they change.',
          child: LiquidGlass(
            weight: GlassWeight.lens,
            radius: Radii.pane,
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              children: const [
                _Readout('steps', '28'),
                _Readout('cfg', '4.50'),
                _Readout('denoise', '0.72'),
                _Readout('size', '1024x1536'),
                _Readout('seed', '1104433390'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) {
    final available = GlassShader.isAvailable;
    return LiquidGlass(
      weight: GlassWeight.vapor,
      radius: Radii.well,
      padding: const EdgeInsets.all(Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            available ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 18,
            color: available ? Palette.iris : Palette.caution,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              available
                  ? 'Impeller is on and the shader loaded. These panes are doing '
                      'real per-pixel refraction of what is behind them.'
                  : 'Impeller or the shader is unavailable on this device, so '
                      'these panes are falling back to a plain blur. Nothing is '
                      'broken - the geometry and tint are identical.',
              style: Type.body.copyWith(fontSize: 13, color: Palette.chalk70),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sample extends StatelessWidget {
  final String title;
  final String note;
  final Widget child;

  const _Sample({required this.title, required this.note, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: Type.micro),
          const SizedBox(height: 2),
          Text(note, style: Type.body.copyWith(fontSize: 12.5, color: Palette.chalk40)),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    );
  }
}

class _Filler extends StatelessWidget {
  final String label;
  final Color? color;
  const _Filler({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: (color ?? Palette.chalk).withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: (color ?? Palette.chalk).withValues(alpha: 0.4)),
            ),
          ),
          const SizedBox(width: Space.md),
          Text(label, style: Type.label),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  final String label;
  final String value;
  const _Readout(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Type.body.copyWith(fontSize: 13, color: Palette.chalk40))),
          Text(value, style: Type.readout),
        ],
      ),
    );
  }
}
