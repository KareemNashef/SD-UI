// ==================== Dev Harness ==================== //

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/dev/generation_lab.dart';
import 'package:sd_companion/ui/dev/glass_lab.dart';
import 'package:sd_companion/ui/dev/state_inspector.dart';

import 'package:sd_companion/ui/glass/glass_tokens.dart';
import 'package:sd_companion/ui/glass/liquid_glass.dart';

/// A scratch screen for checking the rebuild on a real device.
///
/// This exists so the two things that are easy to get wrong - does the glass
/// actually refract on this hardware, and do the stores actually drive the
/// UI - can be answered by looking at a phone rather than by reasoning about
/// the code. It is not part of the product; it will be dropped once the real
/// Stage is built on top of the same pieces.
class DevHarness extends StatefulWidget {
  const DevHarness({super.key});

  @override
  State<DevHarness> createState() => _DevHarnessState();
}

class _DevHarnessState extends State<DevHarness> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void_,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Something colourful for the glass to bend. Stands in for the
          // generated image the real Stage will show.
          const _Backdrop(),

          SafeArea(
            child: Column(
              children: [
                const _Header(),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: const [GlassLab(), GenerationLab(), StateInspector()],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: _Switcher(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The drifting colour field the glass sits over.
class _Backdrop extends StatefulWidget {
  const _Backdrop();

  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 26))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Motion is what proves the refraction is live rather than a static
    // gradient, so it stays on unless the OS asks otherwise.
    final reduce = MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = reduce ? 0.0 : _c.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + 2 * t, -1),
                end: Alignment(1 - 2 * t, 1),
                colors: const [
                  Color(0xFF4C2AB8),
                  Color(0xFFFF8A4C),
                  Color(0xFF1FA5D6),
                  Color(0xFFE0479B),
                ],
                stops: const [0.0, 0.35, 0.68, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.iris,
              boxShadow: [
                BoxShadow(
                  color: Palette.iris.withValues(alpha: 0.7),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'liquid_glass_renderer',
              style: Type.label,
            ),
          ),
          Text('DEV', style: Type.micro),
        ],
      ),
    );
  }
}

class _Switcher extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _Switcher({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: LiquidPill(
        child: Row(
          children: [
            _tab(0, 'Glass', Icons.blur_on_rounded),
            _tab(1, 'Run', Icons.auto_awesome_rounded),
            _tab(2, 'State', Icons.data_object_rounded),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i, String label, IconData icon) {
    final selected = index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.pane,
          curve: Motion.ease,
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected ? Palette.chalk : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: selected ? Palette.void_ : Palette.chalk40),
              const SizedBox(width: 6),
              Text(
                label,
                style: Type.label.copyWith(
                  color: selected ? Palette.void_ : Palette.chalk40,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped pane of lens glass.
class LiquidPill extends StatelessWidget {
  final Widget child;
  const LiquidPill({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      GlassSurface(radius: Radii.pill, child: child);
}
