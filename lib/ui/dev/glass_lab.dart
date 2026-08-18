// ==================== Glass Lab ==================== //

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/glass/glass_controls.dart';
import 'package:sd_companion/ui/glass/glass_tokens.dart';
import 'package:sd_companion/ui/glass/liquid_glass.dart';

/// The material and its controls, on live moving colour.
///
/// Built on `liquid_glass_renderer`, so these panes do genuine per-pixel
/// refraction rather than the blur-with-a-border the first attempt shipped.
///
/// What to look for:
///  * the three weights should be *obviously* different - Prism visibly
///    lenses and colour-fringes the background, Vapor barely touches it;
///  * every control should flex under a finger, because pressing animates
///    the glass optics rather than swapping an opacity;
///  * the specular highlight should swing toward where you touch.
class GlassLab extends StatefulWidget {
  const GlassLab({super.key});

  @override
  State<GlassLab> createState() => _GlassLabState();
}

class _GlassLabState extends State<GlassLab> {
  double _steps = 28;
  double _cfg = 4.5;
  bool _randomSeed = true;
  bool _hires = false;
  String _mode = 'txt2img';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        // ===== The three weights, side by side ===== //
        Text('WEIGHTS', style: Type.micro),
        const SizedBox(height: 2),
        Text(
          'These must look clearly different from each other.',
          style: Type.body.copyWith(fontSize: 12.5, color: Palette.chalk40),
        ),
        const SizedBox(height: Space.md),
        SizedBox(
          height: 108,
          child: Row(
            children: [
              Expanded(child: _WeightSample(weight: GlassWeight.vapor, name: 'Vapor')),
              const SizedBox(width: Space.md),
              Expanded(child: _WeightSample(weight: GlassWeight.lens, name: 'Lens')),
              const SizedBox(width: Space.md),
              Expanded(child: _WeightSample(weight: GlassWeight.prism, name: 'Prism')),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),

        // ===== Buttons ===== //
        _Section(
          title: 'BUTTONS',
          note: 'Press and hold - the slab thins and the highlight moves to your finger.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: GlassButton(label: 'Plain', onPressed: () {})),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: GlassButton(
                      label: 'Forge',
                      icon: Icons.dns_rounded,
                      tint: Palette.ember,
                      filled: true,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'ComfyUI',
                      icon: Icons.hub_rounded,
                      tint: Palette.iris,
                      filled: true,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(child: GlassButton(label: 'Disabled')),
                ],
              ),
            ],
          ),
        ),

        // ===== Sliders ===== //
        _Section(
          title: 'SLIDERS',
          note: 'The thumb is a bead of Prism glass. Drag it across the colour.',
          child: GlassSurface(
            weight: GlassWeight.lens,
            radius: Radii.pane,
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              children: [
                GlassSlider(
                  label: 'Steps',
                  value: _steps,
                  min: 1,
                  max: 60,
                  divisions: 59,
                  tint: Palette.iris,
                  format: (v) => v.round().toString(),
                  onChanged: (v) => setState(() => _steps = v),
                ),
                const SizedBox(height: Space.lg),
                GlassSlider(
                  label: 'CFG Scale',
                  value: _cfg,
                  min: 1,
                  max: 15,
                  tint: Palette.ember,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _cfg = v),
                ),
              ],
            ),
          ),
        ),

        // ===== Selector ===== //
        _Section(
          title: 'SELECTOR',
          note: 'Only the selected segment is real glass - the rest are holes in the track.',
          child: GlassSegmented<String>(
            value: _mode,
            tint: Palette.iris,
            onChanged: (v) => setState(() => _mode = v),
            segments: const [
              GlassSegment(value: 'txt2img', label: 'Text', icon: Icons.title_rounded),
              GlassSegment(value: 'img2img', label: 'Image', icon: Icons.image_rounded),
              GlassSegment(value: 'inpaint', label: 'Inpaint', icon: Icons.brush_rounded),
            ],
          ),
        ),

        // ===== Switches ===== //
        _Section(
          title: 'SWITCHES',
          note: 'The knob is a glass bead that tints as it travels.',
          child: GlassSurface(
            weight: GlassWeight.lens,
            radius: Radii.pane,
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              children: [
                _SwitchRow(
                  label: 'Random seed',
                  value: _randomSeed,
                  tint: Palette.iris,
                  onChanged: (v) => setState(() => _randomSeed = v),
                ),
                const SizedBox(height: Space.lg),
                _SwitchRow(
                  label: 'Hires fix',
                  value: _hires,
                  tint: Palette.ember,
                  onChanged: (v) => setState(() => _hires = v),
                ),
              ],
            ),
          ),
        ),

        // ===== Mono numerals ===== //
        _Section(
          title: 'MONO NUMERALS',
          note: 'Tabular figures - these must not shift as the values above change.',
          child: GlassSurface(
            weight: GlassWeight.lens,
            radius: Radii.pane,
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              children: [
                _Readout('steps', _steps.round().toString()),
                _Readout('cfg', _cfg.toStringAsFixed(2)),
                _Readout('mode', _mode),
                _Readout('seed', _randomSeed ? 'random' : '1104433390'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeightSample extends StatelessWidget {
  final GlassWeight weight;
  final String name;
  const _WeightSample({required this.weight, required this.name});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      weight: weight,
      radius: Radii.pane,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: Type.label),
            const SizedBox(height: 2),
            Text('${weight.thickness.round()}', style: Type.readout),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String note;
  final Widget child;

  const _Section({required this.title, required this.note, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Type.micro),
          const SizedBox(height: 2),
          Text(note, style: Type.body.copyWith(fontSize: 12.5, color: Palette.chalk40)),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final Color tint;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.tint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: Type.label)),
        GlassSwitch(value: value, tint: tint, onChanged: onChanged),
      ],
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
          Expanded(
            child: Text(label,
                style: Type.body.copyWith(fontSize: 13, color: Palette.chalk40)),
          ),
          Text(value, style: Type.readout),
        ],
      ),
    );
  }
}
