// ==================== Stitch Modal ====================

// Flutter imports
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

const _kGreen = Color(0xFF15803D);
const _kGreenDim = Color(0x2215803D);
const _kGreenBorder = Color(0x4415803D);
const _kRadius = 20.0;

/// Background thread Isolate function to Composite the images together.
Future<Map<String, dynamic>> _stitchImageIsolate(Map<String, dynamic> args) async {
  final Uint8List baseBytes = args['base'];
  final Uint8List overlayBytes = args['overlay'];
  final int x = args['x'];
  final int y = args['y'];

  final img.Image? baseImg = img.decodeImage(baseBytes);
  final img.Image? overlayImg = img.decodeImage(overlayBytes);

  if (baseImg == null || overlayImg == null) throw Exception('Unable to decode images');

  // Overlays the edited image onto the base image
  img.compositeImage(baseImg, overlayImg, dstX: x, dstY: y);

  final resultBytes = Uint8List.fromList(img.encodePng(baseImg));
  return {'bytes': resultBytes};
}

void showStitchModal(BuildContext context) {
  GlassModal.show(context, heightFactor: 0.92, child: const _StitchModalContent());
}

class _StitchModalContent extends StatefulWidget {
  const _StitchModalContent();

  @override
  State<_StitchModalContent> createState() => _StitchModalContentState();
}

class _StitchModalContentState extends State<_StitchModalContent> {
  Uint8List? _baseBytes;
  Size? _baseSize;

  Uint8List? _overlayBytes;
  Size? _overlaySize;

  final TextEditingController _xCtrl = TextEditingController();
  final TextEditingController _yCtrl = TextEditingController();

  bool _processing = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the coordinates with the globals
    _xCtrl.text = globalLastCropX.toString();
    _yCtrl.text = globalLastCropY.toString();
  }

  @override
  void dispose() {
    _xCtrl.dispose();
    _yCtrl.dispose();
    super.dispose();
  }

  int get _currentX => int.tryParse(_xCtrl.text) ?? 0;
  int get _currentY => int.tryParse(_yCtrl.text) ?? 0;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white)),
          backgroundColor: error ? const Color(0xFFB00020) : const Color(0xFF1B6B49),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _pickResultImage(bool isBase) async {
    final availableImages = globalResultImages.value.toList();
    if (availableImages.isEmpty) {
      _snack('No images available in results', error: true);
      return;
    }

    final selectedUrl = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ResultsPickerSheet(images: availableImages),
    );

    if (selectedUrl != null) {
      setState(() => _processing = true);
      try {
        final dataStr = selectedUrl.split(',').last;
        final bytes = base64Decode(dataStr);
        final ui.Image decodedUI = await decodeImageFromList(bytes);
        final size = Size(decodedUI.width.toDouble(), decodedUI.height.toDouble());

        setState(() {
          if (isBase) {
            _baseBytes = bytes;
            _baseSize = size;
          } else {
            _overlayBytes = bytes;
            _overlaySize = size;
          }
        });
      } catch (e) {
        _snack('Failed to load image: $e', error: true);
      } finally {
        if (mounted) setState(() => _processing = false);
      }
    }
  }

  Future<void> _stitchAndSend() async {
    if (_baseBytes == null || _overlayBytes == null) {
      _snack('Please select both Base and Overlay images', error: true);
      return;
    }

    setState(() => _sending = true);
    try {
      final args = {'base': _baseBytes, 'overlay': _overlayBytes, 'x': _currentX, 'y': _currentY};

      // Run compositing in background thread
      final r = await compute(_stitchImageIsolate, args);
      final stitchedBytes = r['bytes'] as Uint8List;

      final dataUrl = 'data:image/png;base64,${base64Encode(stitchedBytes)}';

      // Update global value notifier
      final current = Set<String>.from(globalResultImages.value);
      final wasAdded = current.add(dataUrl);
      if (!wasAdded) {
        print('Warning: The stitched image was identical to the base image and was swallowed by the Set deduplication.');
      }
      globalResultImages.value = current;

      _snack('Stitched Image Added to Results!');

      if (!mounted) return;

      // 1. Close the modal
      Navigator.of(context).pop();

      // 2. Automatically route the user to the results page so they see it
      navigateToResultsPage();
    } catch (e) {
      _snack('Stitching error: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canStitch = _baseBytes != null && _overlayBytes != null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          const GlassHeader(title: 'Stitch Image', icon: Icons.layers_rounded, iconColor: _kGreen),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Image selection blocks
                      Row(
                        children: [
                          Expanded(
                            child: _ImageSelectorSlot(label: 'Base Image', bytes: _baseBytes, onTap: () => _pickResultImage(true)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ImageSelectorSlot(label: 'Overlay Image', bytes: _overlayBytes, onTap: () => _pickResultImage(false)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Coordinates Form
                      Row(
                        children: [
                          Expanded(
                            child: _CoordField(label: 'X Coordinate', controller: _xCtrl, onChanged: (_) => setState(() {})),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _CoordField(label: 'Y Coordinate', controller: _yCtrl, onChanged: (_) => setState(() {})),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Live Interactive Preview
                      Expanded(
                        child: _GlassCard(
                          padding: EdgeInsets.zero,
                          child: ClipRRect(borderRadius: BorderRadius.circular(_kRadius), child: _baseBytes == null ? _buildEmptyPreview() : _buildInteractivePreview()),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action Button
                      _ActionButton(icon: Icons.auto_awesome_mosaic_rounded, label: 'Stitch & Send to Results', color: canStitch ? _kGreen : Colors.grey.withValues(alpha: 0.3), onTap: canStitch ? _stitchAndSend : () {}),
                    ],
                  ),
                ),

                // Fluid Full Overlay Loader
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
                                const CircularProgressIndicator(color: _kGreen, strokeWidth: 3),
                                const SizedBox(height: 16),
                                Text(
                                  _sending ? 'Compositing Image…' : 'Processing…',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
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

  Widget _buildEmptyPreview() {
    return Container(
      width: double.infinity,
      color: Colors.white.withValues(alpha: 0.02),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_search_rounded, color: Colors.white.withValues(alpha: 0.2), size: 48),
          const SizedBox(height: 12),
          Text('Select a base image to see preview', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _buildInteractivePreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseAspect = _baseSize!.width / _baseSize!.height;

        double renderW = constraints.maxWidth;
        double renderH = renderW / baseAspect;
        if (renderH > constraints.maxHeight) {
          renderH = constraints.maxHeight;
          renderW = renderH * baseAspect;
        }

        final scale = renderW / _baseSize!.width;

        return Center(
          child: SizedBox(
            width: renderW,
            height: renderH,
            child: Stack(
              children: [
                Positioned.fill(child: Image.memory(_baseBytes!, fit: BoxFit.fill)),

                if (_overlayBytes != null && _overlaySize != null)
                  Positioned(
                    left: _currentX * scale,
                    top: _currentY * scale,
                    width: _overlaySize!.width * scale,
                    height: _overlaySize!.height * scale,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        // Allows dragging the overlay fluidly to position it manually
                        final nx = (_currentX + d.delta.dx / scale).clamp(0, _baseSize!.width - _overlaySize!.width);
                        final ny = (_currentY + d.delta.dy / scale).clamp(0, _baseSize!.height - _overlaySize!.height);

                        _xCtrl.text = nx.round().toString();
                        _yCtrl.text = ny.round().toString();
                        setState(() {});
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: _kGreen, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 15, spreadRadius: -2)],
                        ),
                        child: Image.memory(_overlayBytes!, fit: BoxFit.fill),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------
// Sub-Components
// ---------------------------------------------------------

class _ImageSelectorSlot extends StatelessWidget {
  const _ImageSelectorSlot({required this.label, required this.bytes, required this.onTap});

  final String label;
  final Uint8List? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              height: 70,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.black.withValues(alpha: 0.3),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: bytes == null
                  ? const Center(child: Icon(Icons.add_photo_alternate_rounded, color: _kGreen, size: 28))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(bytes!, fit: BoxFit.cover),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordField extends StatelessWidget {
  const _CoordField({required this.label, required this.controller, required this.onChanged});

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsPickerSheet extends StatelessWidget {
  const _ResultsPickerSheet({required this.images});
  final List<String> images;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: _kRadius,
      backgroundColor: AppTheme.glassBackground,
      borderColor: AppTheme.glassBorder,
      padding: EdgeInsets.zero,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.5,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Image from Results',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: images.length,
                itemBuilder: (context, index) {
                  final dataStr = images[index].split(',').last;
                  final bytes = base64Decode(dataStr);
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop(images[index]),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
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
    return GlassContainer(borderRadius: _kRadius, backgroundColor: AppTheme.glassBackground, borderColor: AppTheme.glassBorder, padding: padding ?? const EdgeInsets.all(18), child: child);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

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
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
