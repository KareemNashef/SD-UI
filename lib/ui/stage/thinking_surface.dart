// ==================== Thinking Surface ==================== //
//
// What the prompt box becomes while a language model is writing into it.
//
// A percentage bar is the wrong instrument here. The server reports one only
// while it loads a model; the rest of the time - reading the prompt,
// reasoning, writing - there is no total to be a fraction of, because
// nothing knows how long the answer will be. What there *is* is words, and
// they arrive about eight times a second.
//
// So this shows the words. Behind them, three washes of the accent colour
// drift and breathe on slow, mutually-prime sine paths, with small bubbles
// rising through - the drift is what makes a wait read as *thinking* rather
// than as hanging, and it costs one repainting layer.
//
// It stays inside the Desk language: the accent and its two tints, on
// paper, inside the same ink border and hard shadow as the field it
// replaces - so nothing shifts when it appears, and nothing about it looks
// borrowed from another app. The softness is entirely in the gradients.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:sd_companion/domain/generation/thinking_update.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// The tail of the stream that is worth showing. Long enough to read a
/// sentence in, short enough that laying it out costs nothing.
const _tailLength = 260;

class ThinkingSurface extends StatefulWidget {
  final String label;
  final ThinkingUpdate update;

  /// Shown before the model has said anything at all, which on a cold start
  /// can be several seconds of loading.
  final String waitingFor;

  const ThinkingSurface({
    super.key,
    required this.label,
    required this.update,
    this.waitingFor = 'WAKING THE MODEL',
  });

  @override
  State<ThinkingSurface> createState() => _ThinkingSurfaceState();
}

class _ThinkingSurfaceState extends State<ThinkingSurface>
    with SingleTickerProviderStateMixin {
  /// Long and prime-ish, so the three washes never line back up into an
  /// obvious loop.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 11000),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  String get _tail {
    final stream = widget.update.stream.trim();
    if (stream.length <= _tailLength) return stream;
    return '…${stream.substring(stream.length - _tailLength)}';
  }

  /// How busy the wash looks. Reading a prompt is calm; writing is not.
  double get _energy => switch (widget.update.phase) {
        'thinking' => 0.75,
        'generating' => 1.0,
        'loading' || 'prompt' => 0.45,
        _ => 0.25,
      };

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final update = widget.update;
    final still = reduceMotion(context);

    final caption = update.label.isEmpty ? widget.waitingFor : update.label;
    final progress = update.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label.toUpperCase(),
                  style: Type.micro.copyWith(color: p.inkFaint)),
            ),
            Text(
              progress == null
                  ? caption
                  : '$caption ${(progress * 100).round()}%',
              style: Type.micro.copyWith(color: p.clay),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Container(
          height: 63,
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(Corner.control),
            border: Border.all(color: p.clay, width: Stroke.live),
            boxShadow: Elevation.raised.shadows(p.ink),
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(Corner.control - Stroke.standard),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DreamWash(energy: _energy, drift: _drift),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.md + 2, vertical: Space.sm),
                  child: _tail.isEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: _Ellipsis(drift: _drift, still: still),
                        )
                      // Bottom-aligned and faded at the top: the newest
                      // words are the ones being written, so they are the
                      // ones that should sit where the eye already is.
                      : ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.white],
                            stops: [0, 0.55],
                          ).createShader(rect),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              _tail,
                              textAlign: TextAlign.left,
                              style: Type.body.copyWith(color: p.ink),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Three dots breathing in turn, for the seconds before the first word.
class _Ellipsis extends StatelessWidget {
  final Animation<double> drift;
  final bool still;

  const _Ellipsis({required this.drift, required this.still});

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return AnimatedBuilder(
      animation: drift,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            Builder(builder: (context) {
              final phase = (drift.value * 3 + i / 3) % 1.0;
              final swell = still ? 0.6 : (math.sin(phase * math.pi * 2) + 1) / 2;
              return Container(
                width: 7 + swell * 3,
                height: 7 + swell * 3,
                decoration: BoxDecoration(
                  color: Color.lerp(p.inkFaint, p.clay, swell),
                  shape: BoxShape.circle,
                ),
              );
            }),
            if (i < 2) const SizedBox(width: Space.sm),
          ],
        ],
      ),
    );
  }
}

/// The drifting wash itself, so the canvas can wear it during a generation
/// and the prompt box during a rewrite without two of them existing.
class DreamWash extends StatefulWidget {
  /// How busy it looks, 0 to 1.
  final double energy;

  /// An existing loop to ride, when the caller already has one. Given none,
  /// it runs its own.
  final Animation<double>? drift;

  /// Multiplies the wash radius, which is otherwise a multiple of the box's
  /// own height. A tall box needs no help; a 14pt progress strip needs the
  /// washes an order of magnitude wider than it is tall, or three specks
  /// crawl along it instead of colour moving through it.
  final double scale;

  const DreamWash({
    super.key,
    this.energy = 0.7,
    this.drift,
    this.scale = 1,
  });

  @override
  State<DreamWash> createState() => _DreamWashState();
}

class _DreamWashState extends State<DreamWash>
    with SingleTickerProviderStateMixin {
  AnimationController? _own;

  Animation<double> get _drift =>
      widget.drift ??
      (_own ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 11000),
      )..repeat());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final still = reduceMotion(context);
    final drift = _drift;
    return AnimatedBuilder(
      animation: drift,
      builder: (context, _) => CustomPaint(
        painter: _DreamPainter(
          // Held still rather than frozen at zero: the washes are the
          // state, so with motion off they simply sit where they are
          // instead of vanishing.
          t: still ? 0.2 : drift.value,
          energy: still ? 0.4 : widget.energy,
          scale: widget.scale,
          accent: p.clay,
          pale: Color.lerp(p.clay, p.paper, 0.62)!,
          deep: Color.lerp(p.clay, p.ink, 0.35)!,
        ),
      ),
    );
  }
}

class _DreamPainter extends CustomPainter {
  final double t;
  final double energy;
  final double scale;
  final Color accent;
  final Color pale;
  final Color deep;

  const _DreamPainter({
    required this.t,
    required this.energy,
    required this.scale,
    required this.accent,
    required this.pale,
    required this.deep,
  });

  /// Three washes on paths that do not share a period, so the pattern never
  /// visibly repeats. The numbers are only chosen to be mutually awkward.
  static const _paths = [
    (colour: 0, speed: 1.0, ax: 0.30, ay: 0.22, cx: 0.28, cy: 0.45, r: 0.95),
    (colour: 1, speed: 0.63, ax: 0.34, ay: 0.30, cx: 0.62, cy: 0.55, r: 1.15),
    (colour: 2, speed: 1.41, ax: 0.26, ay: 0.18, cx: 0.48, cy: 0.40, r: 0.80),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const tau = math.pi * 2;
    for (final path in _paths) {
      final phase = t * path.speed * tau;
      final centre = Offset(
        (path.cx + math.sin(phase) * path.ax * (0.5 + energy / 2)) * size.width,
        (path.cy + math.cos(phase * 1.3) * path.ay) * size.height,
      );
      final radius =
          size.height * path.r * scale * (0.85 + 0.15 * math.sin(phase * 0.7));
      final colour = switch (path.colour) {
        0 => accent,
        1 => pale,
        _ => deep,
      };
      // A radial fade rather than a blur: same softness, none of the cost,
      // and it stays a flat fill in the way the rest of the surface is.
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(centre, radius, [
            colour.withValues(alpha: 0.30 * energy),
            colour.withValues(alpha: 0),
          ]),
      );
    }

    // Bubbles, rising and fading. Small, few, and slower than the washes -
    // enough to read as movement without becoming weather.
    for (var i = 0; i < 7; i++) {
      final seed = i / 7;
      final rise = (t * (0.5 + seed * 0.8) + seed) % 1.0;
      final x = ((seed * 1.618) % 1.0) * size.width +
          math.sin((t + seed) * tau) * 6;
      final y = size.height * (1.15 - rise * 1.3);
      final fade = math.sin(rise * math.pi).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x, y),
        1.5 + seed * 2.5,
        Paint()..color = accent.withValues(alpha: 0.16 * fade * energy),
      );
    }
  }

  @override
  bool shouldRepaint(_DreamPainter old) =>
      old.t != t ||
      old.energy != energy ||
      old.scale != scale ||
      old.accent != accent;
}

// ==================== Dream Bar ==================== //

/// How far a generation has got, said in the same language as the canvas it
/// floats on.
///
/// [DeskProgress] is a ruler - a framed track, ten tick marks, a brass tab
/// carrying the number - and that is exactly right in a drawer, where a
/// ruler is one of the objects on the desk. Laid over a picture that is
/// being dreamt up it read as a piece of machinery bolted to a daydream.
///
/// This is the same instrument as the wash behind it: a window with the
/// drift showing through, filled as far as the run has got. With no number
/// to report the whole strip drifts, which is the honest picture of a
/// server that is working and cannot say how long for.
class DreamBar extends StatelessWidget {
  /// Null renders the indeterminate drift across the whole strip.
  final double? fraction;
  final String? caption;

  const DreamBar({super.key, this.fraction, this.caption});

  static const _height = 14.0;

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final f = fraction?.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: _height,
          decoration: BoxDecoration(
            // Translucent, because it lies on the picture: the frame has to
            // be legible over a dark image and a pale one, without becoming
            // a slab across the middle of either.
            color: p.paper.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(_height / 2),
            border: Border.all(color: p.ink.withValues(alpha: 0.35), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_height / 2),
            child: f == null
                ? const DreamWash(energy: 0.8, scale: 9)
                : Align(
                    alignment: Alignment.centerLeft,
                    // Grows into place rather than jumping: a ComfyUI run
                    // reports in steps, and a bar that teleports between
                    // them reads as stuttering rather than as progress.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: f, end: f),
                      duration: Motion.fade,
                      curve: Motion.ease,
                      builder: (context, value, child) => FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: child,
                      ),
                      child: const DreamWash(energy: 1, scale: 9),
                    ),
                  ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: Text(caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.micro.copyWith(color: p.inkMuted)),
              ),
              if (f != null)
                Text('${(f * 100).round()}%',
                    style: Type.micro.copyWith(color: p.clay)),
            ],
          ),
        ],
      ],
    );
  }
}
