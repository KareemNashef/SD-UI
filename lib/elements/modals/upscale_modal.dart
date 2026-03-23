// ==================== Upscale Modal ====================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Upscale Modal Implementation

const _kGreen = Color(0xFF15803D);
const _kGreenDim = Color(0x2215803D);
const _kGreenBorder = Color(0x4415803D);
const _kRadius = 20.0;

/// Shows the upscale modal. Result image can be sent to the results carousel.
/// If [initialImageBytes] is provided, the modal opens with that image loaded.
void showUpscaleModal(BuildContext context, {Uint8List? initialImageBytes}) {
  GlassModal.show(context, heightFactor: 0.92, child: _UpscaleModalContent(initialImageBytes: initialImageBytes));
}

class _UpscaleModalContent extends StatefulWidget {
  final Uint8List? initialImageBytes;

  const _UpscaleModalContent({this.initialImageBytes});

  @override
  State<_UpscaleModalContent> createState() => _UpscaleModalContentState();
}

class _UpscaleModalContentState extends State<_UpscaleModalContent> {
  final _picker = ImagePicker();

  Uint8List? _originalBytes;
  int? _origW, _origH;

  final ValueNotifier<int> _resolutionNotifier = ValueNotifier(1080);

  bool _processing = false;
  bool _sending = false;
  double? _progress;
  String? _statusText;

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
    _resolutionNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadFromBytes(Uint8List bytes) async {
    setState(() => _processing = true);
    try {
      final decoded = await compute(img.decodeImage, bytes);
      if (decoded != null) {
        setState(() {
          _originalBytes = bytes;
          _origW = decoded.width;
          _origH = decoded.height;
        });
      }
    } catch (e) {
      _snack('Error analyzing image: $e', error: true);
    } finally {
      setState(() => _processing = false);
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
      _originalBytes = null;
      _origW = null;
      _origH = null;
      _processing = true;
    });

    try {
      final bytes = await picked.readAsBytes();
      final decoded = await compute(img.decodeImage, bytes);
      if (decoded != null) {
        setState(() {
          _originalBytes = bytes;
          _origW = decoded.width;
          _origH = decoded.height;
        });
      }
    } catch (e) {
      _snack('Error loading image: $e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _upscaleAndSend() async {
    if (_sending || _originalBytes == null) return;

    setState(() {
      _sending = true;
      _processing = true;
      _progress = null;
      _statusText = null;
    });

    try {
      final upscaledDataUrl = await globalBackend.upscaleSeedVR2(
        imageBytes: _originalBytes!,
        resolution: _resolutionNotifier.value,
        onProgress: (progressData) {
          if (mounted) {
            setState(() {
              _progress = (progressData['progress'] as num?)?.toDouble();
              _statusText = progressData['status'] as String?;
            });
          }
        },
      );

      if (!mounted) return;

      final current = Set<String>.from(globalResultImages.value);
      current.add(upscaledDataUrl);
      globalResultImages.value = current;

      _snack('Image upscaled successfully!');
      Navigator.of(context).pop();
      navigateToResultsPage();
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _originalBytes != null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          const GlassHeader(title: 'Upscale Image', icon: Icons.hd_rounded, iconColor: _kGreen),
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
                        child: _ViewerCard(hasImage: hasImage, originalBytes: _originalBytes, onPickImage: _pickImage),
                      ),
                      if (hasImage) ...[const SizedBox(height: 16), _GlassCard(child: _buildUpscaleControls())],
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
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(_kRadius)),
                          child: Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 40),
                              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF121212),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: _kGreen.withValues(alpha: 0.3), width: 1.5),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 30, spreadRadius: 10),
                                  BoxShadow(color: _kGreen.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 0),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(width: 70, height: 70, child: CircularProgressIndicator(color: _kGreen.withValues(alpha: 0.15), strokeWidth: 3.5, value: 1.0)),
                                      SizedBox(
                                        width: 70,
                                        height: 70,
                                        child: CircularProgressIndicator(color: _kGreen, strokeWidth: 3.5, value: _progress),
                                      ),
                                      const Icon(Icons.auto_awesome_rounded, color: _kGreen, size: 28),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    _statusText?.toUpperCase() ?? (_sending ? 'UPSCALE IN PROGRESS' : 'PREPARING...'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                                  ),
                                  if (_progress != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      '${(_progress! * 100).toInt()}%',
                                      style: const TextStyle(color: _kGreen, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                  if (_sending) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Enhancing details & resolution',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ],
                              ),
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

  Widget _buildUpscaleControls() {
    return ValueListenableBuilder<int>(
      valueListenable: _resolutionNotifier,
      builder: (context, resolution, child) {
        int targetW = resolution;
        int targetH = resolution;

        if (_origW != null && _origH != null) {
          final double aspect = _origW! / _origH!;
          if (_origW! < _origH!) {
            // Width is smaller
            targetW = resolution;
            targetH = (resolution / aspect).round();
          } else {
            // Height is smaller or equal
            targetH = resolution;
            targetW = (resolution * aspect).round();
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Presets',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                _Pill(
                  child: Text(
                    'Target: ${resolution}p',
                    style: const TextStyle(color: _kGreen, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [_buildPresetBtn(720, 'HD'), const SizedBox(width: 8), _buildPresetBtn(1080, 'FHD'), const SizedBox(width: 8), _buildPresetBtn(1440, 'QHD')]),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _DimChip(label: 'Original', value: _origW != null ? '$_origW × $_origH' : '--- × ---'),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.keyboard_double_arrow_right_rounded, color: Colors.white24, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: _DimChip(label: 'Resulting', value: '$targetW × $targetH', accent: true),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPresetBtn(int val, String label) {
    return Expanded(
      child: ValueListenableBuilder<int>(
        valueListenable: _resolutionNotifier,
        builder: (context, current, _) {
          final isSelected = current == val;
          return GestureDetector(
            onTap: () => _resolutionNotifier.value = val,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? _kGreen : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSelected ? _kGreen : Colors.white.withValues(alpha: 0.1)),
              ),
              child: Center(
                child: Text(
                  '$val ($label)',
                  style: TextStyle(color: isSelected ? Colors.black87 : Colors.white70, fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions(bool hasImage) {
    if (!hasImage) {
      return _ActionButton(icon: Icons.add_photo_alternate_rounded, label: 'Select Image', color: _kGreen, onTap: _pickImage);
    }
    return Row(
      children: [
        _IconBtn(icon: Icons.photo_library_outlined, color: Colors.white70, onTap: _pickImage),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(icon: Icons.auto_awesome_rounded, label: 'Upscale', color: _kGreen, onTap: _upscaleAndSend),
        ),
      ],
    );
  }
}

class _ViewerCard extends StatelessWidget {
  const _ViewerCard({required this.hasImage, required this.originalBytes, required this.onPickImage});

  final bool hasImage;
  final Uint8List? originalBytes;
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
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kRadius),
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: InteractiveViewer(minScale: 1.0, maxScale: 10.0, child: Image.memory(originalBytes!, fit: BoxFit.contain, gaplessPlayback: true)),
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
          gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
              child: const Icon(Icons.add_photo_alternate_rounded, color: _kGreen, size: 26),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tap to select an image',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text('PNG, JPG, WEBP supported', style: TextStyle(color: Colors.white30, fontSize: 12)),
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

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
  const _DimChip({required this.label, required this.value, this.accent = false});
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
        border: Border.all(color: accent ? _kGreenBorder : Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: accent ? _kGreen : Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
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
                Icon(icon, size: 20, color: Colors.black87),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3),
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
  const _IconBtn({required this.icon, required this.color, required this.onTap});

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
