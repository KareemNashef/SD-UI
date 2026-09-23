// ==================== Prompt Tools ==================== //
//
// The three things you can do *to* the prompt - reach for an old one, have
// one written, have one read off a picture - behind one button.
//
// They used to be a row of their own under the field. Three buttons, 42
// points, permanently on screen for actions taken once or twice a session,
// on a page where the canvas had about three hundred points to work with.
// A card that opens above a single `⋯` costs nothing until it is wanted.
//
// The writer's dial rides on the button itself, as ten pips: readable at a
// glance without being touched, and set by holding the strip and dragging
// along it. A tenth of a range is a coarse thing to ask for, so a strip of
// ten is the honest shape for it - far more so than a ruler that could land
// anywhere between them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// 1 to 10, mild to extreme. The number the prompt writer takes.
const kIntensityMin = 1;
const kIntensityMax = 10;

class PromptTools extends StatefulWidget {
  final bool canWrite;
  final bool canDescribe;

  /// True while any of them is running: the card still opens, but nothing
  /// in it can be started twice.
  final bool busy;

  final int intensity;
  final ValueChanged<int> onIntensity;

  final VoidCallback onPrompts;
  final VoidCallback onWrite;
  final VoidCallback onDescribe;

  /// Matches the height of the field it sits beside.
  final double height;

  const PromptTools({
    super.key,
    required this.canWrite,
    required this.canDescribe,
    required this.busy,
    required this.intensity,
    required this.onIntensity,
    required this.onPrompts,
    required this.onWrite,
    required this.onDescribe,
    this.height = Space.touch,
  });

  @override
  State<PromptTools> createState() => _PromptToolsState();
}

class _PromptToolsState extends State<PromptTools>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  OverlayEntry? _entry;

  /// Whether the card is meant to be on screen. Kept apart from [_entry],
  /// which outlives it by the length of the closing animation.
  bool _shown = false;

  /// Out faster than in. A card arriving is the app showing you something
  /// and can afford to be watched doing it; a card leaving is in the way.
  ///
  /// Built in `initState`, not lazily: a `late final` initialiser that is
  /// never read until `dispose` creates its ticker *during* the unmount,
  /// which looks up an ancestor that is already gone. That is exactly what
  /// happens to a composer whose tools were never opened - which is most of
  /// them.
  late final AnimationController _open;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _remove();
    _open.dispose();
    super.dispose();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void _close() {
    if (!_shown) return;
    _shown = false;
    if (mounted) setState(() {});
    _open.reverse().whenComplete(() {
      // Reopened mid-close: the entry on screen is the *new* card, and
      // tearing it down here would take that one with it.
      if (_shown) return;
      _remove();
      if (mounted) setState(() {});
    });
  }

  /// Runs a tool and shuts the card. The card is a way in, not a place to
  /// stay - except for the dial, which is a setting and leaves it open.
  void _pick(VoidCallback action) {
    _close();
    action();
  }

  void _toggle() {
    if (_shown) {
      _close();
      return;
    }
    _shown = true;
    final entry = _entry ??= _buildEntry();
    if (!entry.mounted) Overlay.of(context).insert(entry);
    _open.forward();
    setState(() {});
  }

  OverlayEntry _buildEntry() {
    final p = DeskTheme.of(context);
    final mode = DeskTheme.modeOf(context);
    final curve = CurvedAnimation(
      parent: _open,
      // A slight overshoot on the way in, so the card lands rather than
      // appears; a plain ease on the way out.
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    return OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          // Above the trigger, not below it: this lives at the bottom of
          // the screen, and a card dropped downwards would open into the
          // keyboard or off the edge.
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -Space.sm),
            child: DeskTheme(
              palette: p,
              mode: mode,
              child: Align(
                alignment: Alignment.bottomRight,
                child: Material(
                  type: MaterialType.transparency,
                  child: AnimatedBuilder(
                    animation: _open,
                    child: _card(p),
                    builder: (context, child) => Opacity(
                      // Fades on the raw value rather than the overshooting
                      // curve, which would drive opacity past 1 and clip.
                      opacity: _open.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        // Rises out of the button it belongs to and grows
                        // from that same corner, so it reads as the `⋯`
                        // opening rather than as a panel appearing over it.
                        offset: Offset(0, (1 - curve.value) * 14),
                        child: Transform.scale(
                          scale: 0.88 + 0.12 * curve.value,
                          alignment: Alignment.bottomRight,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(DeskPalette p) => Container(
        width: 232,
        padding: const EdgeInsets.all(Space.sm),
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(Corner.panel),
          border: Border.all(color: p.ink, width: Stroke.frame),
          boxShadow: Elevation.drawer.shadows(p.ink),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(p, Icons.history_rounded, 'Prompts',
                () => _pick(widget.onPrompts)),
            if (widget.canWrite) ...[
              const SizedBox(height: Space.sm),
              WriteAction(
                intensity: widget.intensity,
                onIntensity: (value) {
                  widget.onIntensity(value);
                  // The dial is a setting, so the card stays: it rebuilds
                  // in place rather than closing under the finger.
                  _entry?.markNeedsBuild();
                },
                onTap: widget.busy ? null : () => _pick(widget.onWrite),
              ),
            ],
            if (widget.canDescribe) ...[
              const SizedBox(height: Space.sm),
              _row(p, Icons.image_search_rounded, 'Describe',
                  () => _pick(widget.onDescribe)),
            ],
          ],
        ),
      );

  Widget _row(DeskPalette p, IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.busy ? null : onTap,
        child: Container(
          height: Space.touch,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(Corner.control),
            border: Border.all(color: p.ink, width: Stroke.standard),
            boxShadow: Elevation.rest.shadows(p.ink),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16, color: widget.busy ? p.inkFaint : p.inkMuted),
              const SizedBox(width: Space.sm),
              Text(label,
                  style: Type.label
                      .copyWith(color: widget.busy ? p.inkFaint : p.ink)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Container(
          width: Space.touch,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(Corner.control),
            border: Border.all(
              color: _shown ? p.clay : p.ink,
              width: _shown ? Stroke.live : Stroke.standard,
            ),
            boxShadow: Elevation.raised.shadows(p.ink),
          ),
          // Turns as the card opens, and back as it goes. The three dots
          // standing still while something appeared above them is what made
          // the card read as a popup rather than as this button's contents.
          child: AnimatedRotation(
            turns: _shown ? 0.25 : 0,
            duration: Motion.fade,
            curve: Motion.ease,
            child: Icon(Icons.more_horiz_rounded,
                size: 18, color: _shown ? p.clay : p.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// Write, with its dial on it.
///
/// The dial is held and dragged rather than tapped at. A tenth of a 190pt
/// strip is nineteen points wide and four tall, and aiming at one of those
/// on a card that also carries a button meant the misses landed on *Write* -
/// which starts a generation you then have to sit through. So the strip is a
/// 28pt target that claims the gesture the moment it is touched, and holding
/// it magnifies the pips and tracks the finger along them.
class WriteAction extends StatefulWidget {
  /// The pip strip, so a test can aim at the dial rather than the button.
  static const stripKey = ValueKey('write-intensity-strip');

  final int intensity;
  final ValueChanged<int> onIntensity;
  final VoidCallback? onTap;

  const WriteAction({
    super.key,
    required this.intensity,
    required this.onIntensity,
    this.onTap,
  });

  @override
  State<WriteAction> createState() => _WriteActionState();
}

class _WriteActionState extends State<WriteAction> {
  /// The pip strip's own width at the last layout, so a drag can be mapped
  /// onto it without measuring the render object every frame.
  double _stripWidth = 1;

  /// True while a finger is on the dial. It is the only signal that the
  /// gesture has been taken, and without it a hold on a four-point pip
  /// looks exactly like a hold on nothing at all.
  bool _holding = false;

  void _setFrom(double dx) {
    const count = kIntensityMax - kIntensityMin + 1;
    final index = (dx / _stripWidth * count).floor();
    final value = (kIntensityMin + index).clamp(kIntensityMin, kIntensityMax);
    if (value == widget.intensity) return;
    HapticFeedback.selectionClick();
    widget.onIntensity(value);
  }

  void _hold(bool holding) {
    if (_holding == holding) return;
    if (holding) HapticFeedback.mediumImpact();
    setState(() => _holding = holding);
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final enabled = widget.onTap != null;
    final onPaper = p.paper.withValues(alpha: enabled ? 1 : 0.5);

    // The label writes; the strip sets the level. Two targets rather than
    // one surface that has to tell a tap from a drag - which it cannot do
    // without a delay, and a button that hesitates is worse than a button
    // that is slightly smaller.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        padding:
            const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm),
        decoration: BoxDecoration(
          color: p.clay,
          borderRadius: BorderRadius.circular(Corner.control),
          border: Border.all(color: p.ink, width: Stroke.standard),
          boxShadow: Elevation.raised.shadows(p.ink),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.casino_rounded, size: 16, color: onPaper),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    // Says what the strip below it is for, but only while a
                    // finger is on it: a permanent instruction printed on a
                    // button is a sign the control needed one.
                    _holding ? 'INTENSITY' : 'Write',
                    style: Type.label.copyWith(color: onPaper),
                  ),
                ),
                // Grows into a readout under the finger, so the number can
                // be watched without looking down at the pips to count.
                AnimatedDefaultTextStyle(
                  duration: Motion.press,
                  curve: Motion.snap,
                  style: Type.readout.copyWith(
                    color: p.paper,
                    fontSize: _holding ? 20 : 13,
                  ),
                  child: Text('${widget.intensity}'),
                ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                _stripWidth = constraints.maxWidth;
                return GestureDetector(
                  key: WriteAction.stripKey,
                  behavior: HitTestBehavior.opaque,
                  // Claims the tap itself, which is the point of it: an
                  // unclaimed tap here fell through to Write and started a
                  // run that then had to be waited out.
                  onTapDown: (d) => _setFrom(d.localPosition.dx),
                  onLongPressStart: (d) {
                    _hold(true);
                    _setFrom(d.localPosition.dx);
                  },
                  onLongPressMoveUpdate: (d) => _setFrom(d.localPosition.dx),
                  onLongPressEnd: (_) => _hold(false),
                  onLongPressCancel: () => _hold(false),
                  onHorizontalDragStart: (d) {
                    _hold(true);
                    _setFrom(d.localPosition.dx);
                  },
                  onHorizontalDragUpdate: (d) => _setFrom(d.localPosition.dx),
                  onHorizontalDragEnd: (_) => _hold(false),
                  onHorizontalDragCancel: () => _hold(false),
                  child: SizedBox(
                    // A four-point strip is not a touch target; this is,
                    // and the pips sit in the middle of it.
                    height: 28,
                    child: Center(
                      child: AnimatedContainer(
                        duration: Motion.press,
                        curve: Motion.snap,
                        height: _holding ? 16 : 8,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.ink.withValues(alpha: _holding ? 0.28 : 0),
                          borderRadius: BorderRadius.circular(Corner.photo),
                        ),
                        child: Row(
                          children: [
                            for (var i = kIntensityMin;
                                i <= kIntensityMax;
                                i++) ...[
                              Expanded(
                                child: AnimatedContainer(
                                  duration: Motion.press,
                                  curve: Motion.snap,
                                  decoration: BoxDecoration(
                                    color: p.paper.withValues(
                                        alpha: i <= widget.intensity ? 1 : 0.3),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                              if (i < kIntensityMax) const SizedBox(width: 2),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
