// ==================== Resize Modal ====================

// Flutter imports
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Resize Modal Implementation

const _kGreen = Color(0xFF15803D);
const _kGreenDim = Color(0x2215803D);
const _kGreenBorder = Color(0x4415803D);
const _kRadius = 20.0;

Future<img.Image?> _decodeImageIsolate(Uint8List bytes) async {
  return img.decodeImage(bytes);
}

Future<Map<String, dynamic>> _resizeImageIsolate(
  Map<String, dynamic> args,
) async {
  final img.Image src = args['src'];
  final resized = img.copyResize(
    src,
    width: args['targetW'],
    height: args['targetH'],
    interpolation: img.Interpolation.linear,
  );
  return {
    'bytes': Uint8List.fromList(img.encodePng(resized)),
    'width': resized.width,
    'height': resized.height,
  };
}

/// Shows the resize modal. Result image can be sent to the results carousel.
/// If [initialImageBytes] is provided, the modal opens with that image loaded.
void showResizeModal(BuildContext context, {Uint8List? initialImageBytes}) {
  GlassModal.show(
    context,
    heightFactor: 0.92,
    child: _ResizeModalContent(initialImageBytes: initialImageBytes),
  );
}

class _ResizeModalContent extends StatefulWidget {
  final Uint8List? initialImageBytes;

  const _ResizeModalContent({this.initialImageBytes});

  @override
  State<_ResizeModalContent> createState() => _ResizeModalContentState();
}

class _ResizeModalContentState extends State<_ResizeModalContent> {
  final _picker = ImagePicker();

  Uint8List? _originalBytes;
  img.Image? _originalImage;
  Uint8List? _resizedBytes;

  // Performance: ValueNotifiers prevent full screen rebuilds during rapid interactions
  final ValueNotifier<double> _scaleNotifier = ValueNotifier(75.0);
  final ValueNotifier<bool> _compareNotifier = ValueNotifier(false);

  bool _processing = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialImageBytes != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFromBytes(widget.initialImageBytes!);
      });
    }
  }

  @override
  void dispose() {
    _scaleNotifier.dispose();
    _compareNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadFromBytes(Uint8List bytes) async {
    setState(() => _processing = true);
    try {
      final decoded = await compute(_decodeImageIsolate, bytes);
      if (decoded == null) throw Exception('Unable to decode image');
      if (!mounted) return;

      setState(() {
        _originalBytes = bytes;
        _originalImage = decoded;
      });
      await _rebuildResize();
    } catch (e) {
      _snack('Error loading image: $e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    // if (!mounted) return;
    // ScaffoldMessenger.of(context)
    //   ..clearSnackBars()
    //   ..showSnackBar(
    //     SnackBar(
    //       content: Text(msg, style: const TextStyle(color: Colors.white)),
    //       backgroundColor: error
    //           ? const Color(0xFFB00020)
    //           : const Color(0xFF1B6B49),
    //       behavior: SnackBarBehavior.floating,
    //       shape: RoundedRectangleBorder(
    //         borderRadius: BorderRadius.circular(12),
    //       ),
    //       margin: const EdgeInsets.all(16),
    //     ),
    //   );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _processing = true;
      _originalBytes = null;
      _originalImage = null;
      _resizedBytes = null;
      _scaleNotifier.value = 75.0;
    });

    try {
      final bytes = await picked.readAsBytes();
      final decoded = await compute(_decodeImageIsolate, bytes);
      if (decoded == null) throw Exception('Unable to decode image');

      setState(() {
        _originalBytes = bytes;
        _originalImage = decoded;
      });

      await _rebuildResize();
    } catch (e) {
      _snack('Error loading image: $e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _rebuildResize() async {
    final src = _originalImage;
    if (src == null) return;

    final p = (_scaleNotifier.value / 100).clamp(0.01, 1.0);
    final tw = (src.width * p).round().clamp(1, src.width);
    final th = (src.height * p).round().clamp(1, src.height);

    setState(() => _processing = true);
    try {
      final r = await compute(_resizeImageIsolate, {
        'src': src,
        'targetW': tw,
        'targetH': th,
      });
      if (!mounted) return;
      setState(() {
        _resizedBytes = r['bytes'];
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _sendToResults() {
    if (_sending || _resizedBytes == null) return;

    setState(() => _sending = true);
    try {
      final dataUrl = 'data:image/png;base64,${base64Encode(_resizedBytes!)}';
      final current = Set<String>.from(globalResultImages.value);
      current.add(dataUrl);
      globalResultImages.value = current;
      _snack('Added to Results');
      Navigator.of(context).pop();
      navigateToResultsPage();
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _originalImage != null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          const GlassHeader(
            title: 'Resize Image',
            icon: Icons.photo_size_select_large_rounded,
            iconColor: _kGreen,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ViewerCard(
                          hasImage: hasImage,
                          originalBytes: _originalBytes,
                          editedBytes: _resizedBytes,
                          compareNotifier: _compareNotifier,
                          onPickImage: _pickImage,
                        ),
                      ),
                      if (hasImage) ...[
                        const SizedBox(height: 16),
                        _GlassCard(child: _buildResizeControls()),
                      ],
                      const SizedBox(height: 16),
                      _buildActions(hasImage),
                    ],
                  ),
                ),

                // Processing fluid overlay
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: (_processing || _sending)
                      ? Container(
                          key: const ValueKey('overlay'),
                          color: Colors.black.withValues(alpha: 0.65),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  color: _kGreen,
                                  strokeWidth: 3,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _sending
                                      ? 'Adding to Results…'
                                      : 'Processing…',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResizeControls() {
    final origW = _originalImage!.width;
    final origH = _originalImage!.height;

    return ValueListenableBuilder<double>(
      valueListenable: _scaleNotifier,
      builder: (context, scale, child) {
        final double multiplier = scale / 100;
        final int targetW = (origW * multiplier).round().clamp(1, origW);
        final int targetH = (origH * multiplier).round().clamp(1, origH);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Scale Percentage',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                _Pill(
                  child: Text(
                    '${scale.toInt()}%',
                    style: const TextStyle(
                      color: _kGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: _kGreen,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayColor: _kGreen.withValues(alpha: 0.15),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              ),
              child: Slider(
                value: scale,
                min: 10,
                max: 100,
                divisions: 90,
                onChanged: (v) => _scaleNotifier.value = v,
                onChangeEnd: (_) => _rebuildResize(),
              ),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '10%',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
                Text(
                  '100%',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DimChip(label: 'Original', value: '$origW × $origH'),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white24,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DimChip(
                    label: 'Output',
                    value: '$targetW × $targetH',
                    accent: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Hold to Compare Button
            GestureDetector(
              onTapDown: (_) => _compareNotifier.value = true,
              onTapUp: (_) => _compareNotifier.value = false,
              onTapCancel: () => _compareNotifier.value = false,
              child: ValueListenableBuilder<bool>(
                valueListenable: _compareNotifier,
                builder: (context, comparing, child) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 48,
                    decoration: BoxDecoration(
                      color: comparing
                          ? _kGreenDim
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: comparing
                            ? _kGreen
                            : Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.compare_rounded,
                            color: comparing ? _kGreen : Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            comparing ? 'Showing Original' : 'Hold to compare',
                            style: TextStyle(
                              color: comparing ? _kGreen : Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActions(bool hasImage) {
    if (!hasImage) {
      return _ActionButton(
        icon: Icons.add_photo_alternate_rounded,
        label: 'Select Image',
        color: _kGreen,
        onTap: _pickImage,
      );
    }
    return Row(
      children: [
        _IconBtn(
          icon: Icons.photo_library_outlined,
          color: Colors.white70,
          onTap: _pickImage,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.send_rounded,
            label: 'Send to Results',
            color: _kGreen,
            onTap: _sendToResults,
          ),
        ),
      ],
    );
  }
}

class _ViewerCard extends StatelessWidget {
  const _ViewerCard({
    required this.hasImage,
    required this.originalBytes,
    required this.editedBytes,
    required this.compareNotifier,
    required this.onPickImage,
  });

  final bool hasImage;
  final Uint8List? originalBytes;
  final Uint8List? editedBytes;
  final ValueNotifier<bool> compareNotifier;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: EdgeInsets.zero,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: !hasImage || originalBytes == null
            ? _EmptyViewer(onTap: onPickImage)
            : GestureDetector(
                onTap:
                    () {}, // Absorb taps so outer unfocus GestureDetector doesn't close/interrupt while zooming
                behavior: HitTestBehavior.opaque,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kRadius),
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale:
                          10.0, // Allows deep zooming for pixel comparison
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Bottom Layer: Original Image
                          // Always rendered. Keeps the scale perfectly steady.
                          Image.memory(
                            originalBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true, // Prevents flickering
                          ),

                          // Top Layer: Resized Image
                          // Fades to opacity 0.0 when comparing to reveal original.
                          ValueListenableBuilder<bool>(
                            valueListenable: compareNotifier,
                            builder: (context, comparing, child) {
                              return IgnorePointer(
                                // Prevents top layer from intercepting gestures
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 100),
                                  opacity: comparing ? 0.0 : 1.0,
                                  child: Image.memory(
                                    editedBytes ?? originalBytes!,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _EmptyViewer extends StatelessWidget {
  const _EmptyViewer({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kRadius),
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kGreenDim,
                border: Border.all(color: _kGreenBorder),
              ),
              child: const Icon(
                Icons.add_photo_alternate_rounded,
                color: _kGreen,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tap to select an image',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'PNG, JPG, WEBP supported',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: _kRadius,
      backgroundColor: AppTheme.glassBackground,
      borderColor: AppTheme.glassBorder,
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _kGreenDim,
        border: Border.all(color: _kGreenBorder),
      ),
      child: child,
    );
  }
}

class _DimChip extends StatelessWidget {
  const _DimChip({
    required this.label,
    required this.value,
    this.accent = false,
  });
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent ? _kGreenDim : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: accent ? _kGreenBorder : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accent ? _kGreen : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.black87),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}
