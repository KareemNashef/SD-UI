// ==================== Image Tools ==================== //
//
// The two post-generation tools that need a panel rather than a canvas:
// resizing, and reading back what an image says about how it was made.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sd_companion/domain/generation/image_metadata.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// Resize by a percentage or by pinning the longest side.
///
/// Both are offered because they answer different questions: "make this
/// smaller" is proportional, while "fit this under 1024" is a ceiling, and
/// converting between them in your head is exactly the sort of arithmetic
/// the app should be doing.
class ResizeDrawerBody extends StatefulWidget {
  final int width;
  final int height;

  /// Called with the chosen target size when the user confirms.
  final void Function(int width, int height) onApply;

  const ResizeDrawerBody({
    super.key,
    required this.width,
    required this.height,
    required this.onApply,
  });

  @override
  State<ResizeDrawerBody> createState() => _ResizeDrawerBodyState();
}

class _ResizeDrawerBodyState extends State<ResizeDrawerBody> {
  double _percent = 100;

  int get _targetW => (widget.width * _percent / 100).round().clamp(1, 16384);
  int get _targetH => (widget.height * _percent / 100).round().clamp(1, 16384);

  bool get _unchanged => _targetW == widget.width && _targetH == widget.height;

  void _pinLongestSide(int side) {
    final longest = widget.width > widget.height ? widget.width : widget.height;
    setState(() => _percent = (side / longest * 100).clamp(1, 400));
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _Readout(
                  label: 'FROM', value: '${widget.width} × ${widget.height}'),
            ),
            Icon(Icons.arrow_forward_rounded, size: 16, color: p.inkFaint),
            Expanded(
              child: _Readout(
                label: 'TO',
                value: '$_targetW × $_targetH',
                emphasis: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        DeskRuler(
          label: 'Scale',
          value: _percent,
          min: 5,
          max: 200,
          format: (v) => '${v.round()}%',
          onChanged: (v) => setState(() => _percent = v),
        ),
        const SizedBox(height: Space.lg),
        Text('FIT LONGEST SIDE', style: Type.micro.copyWith(color: p.inkFaint)),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            for (final side in const [512, 768, 1024, 1536, 2048]) ...[
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pinLongestSide(side),
                  child: Container(
                    height: Space.touch,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.paper,
                      borderRadius: BorderRadius.circular(Corner.control),
                      border: Border.all(color: p.ink, width: Stroke.standard),
                      boxShadow: Elevation.rest.shadows(p.ink),
                    ),
                    child: Text('$side',
                        style: Type.readout.copyWith(color: p.ink, fontSize: 11)),
                  ),
                ),
              ),
              if (side != 2048) const SizedBox(width: Space.xs),
            ],
          ],
        ),
        const SizedBox(height: Space.lg),
        DeskButton(
          label: 'Resize',
          icon: Icons.photo_size_select_large_rounded,
          kind: DeskButtonKind.primary,
          expand: true,
          onPressed: _unchanged
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onApply(_targetW, _targetH);
                },
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;

  const _Readout({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Type.micro.copyWith(color: p.inkFaint)),
        const SizedBox(height: 2),
        Text(value,
            style: Type.readout
                .copyWith(color: emphasis ? p.clay : p.ink, fontSize: 14)),
      ],
    );
  }
}

/// Shows what a generated image carries in its own PNG chunks.
class MetadataDrawerBody extends StatelessWidget {
  final ImageMetadata metadata;
  final void Function(String message) onCopied;

  const MetadataDrawerBody({
    super.key,
    required this.metadata,
    required this.onCopied,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);

    if (metadata.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: Column(
          children: [
            Icon(Icons.info_outline_rounded, size: 28, color: p.inkFaint),
            const SizedBox(height: Space.md),
            Text(
              'This image carries no generation data.\nIt was probably '
              're-encoded, or saved by a tool that strips it.',
              textAlign: TextAlign.center,
              style: Type.body.copyWith(color: p.inkFaint),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            DeskStamp(label: metadata.sourceLabel, color: DeskPalette.good),
          ],
        ),
        if (metadata.hasPrompt) ...[
          const SizedBox(height: Space.lg),
          _Block(
            label: 'Prompt',
            text: metadata.prompt!,
            onCopy: () => _copy(metadata.prompt!, 'Prompt copied.'),
          ),
        ],
        if (metadata.negativePrompt != null &&
            metadata.negativePrompt!.trim().isNotEmpty) ...[
          const SizedBox(height: Space.md),
          _Block(
            label: 'Negative prompt',
            text: metadata.negativePrompt!,
            onCopy: () =>
                _copy(metadata.negativePrompt!, 'Negative prompt copied.'),
          ),
        ],
        if (metadata.fields.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text('SETTINGS', style: Type.micro.copyWith(color: p.inkFaint)),
          const SizedBox(height: Space.sm),
          for (final entry in metadata.fields.entries)
            Container(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: p.ink.withValues(alpha: 0.15),
                      width: Stroke.hairline),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(entry.key,
                        style: Type.label.copyWith(color: p.inkMuted)),
                  ),
                  Expanded(
                    child: Text(entry.value,
                        style: Type.readout.copyWith(color: p.ink)),
                  ),
                ],
              ),
            ),
        ],
        if (metadata.comfyWorkflow != null) ...[
          const SizedBox(height: Space.lg),
          DeskButton(
            label: 'Copy workflow JSON',
            icon: Icons.copy_rounded,
            expand: true,
            onPressed: () => _copy(metadata.comfyWorkflow!,
                'Workflow JSON copied — paste it into a file to re-import.'),
          ),
        ],
      ],
    );
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    onCopied(message);
  }
}

class _Block extends StatelessWidget {
  final String label;
  final String text;
  final VoidCallback onCopy;

  const _Block({required this.label, required this.text, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label.toUpperCase(),
                  style: Type.micro.copyWith(color: p.inkFaint)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCopy,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: Space.xs),
                child: Icon(Icons.copy_rounded, size: 15, color: p.inkMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: p.paperEdge,
            borderRadius: BorderRadius.circular(Corner.control),
            border: Border.all(color: p.ink, width: Stroke.standard),
          ),
          child: SelectableText(text, style: Type.body.copyWith(color: p.ink)),
        ),
      ],
    );
  }
}
