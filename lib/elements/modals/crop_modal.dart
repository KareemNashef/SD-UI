// ==================== Crop Modal ====================

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

// Crop Modal Implementation

const _kGreen = Color(0xFF15803D);
const _kGreenDim = Color(0x2215803D);
const _kGreenBorder = Color(0x4415803D);
const _kRadius = 20.0;

Future<img.Image?> _decodeImageIsolate(Uint8List bytes) async {
  return img.decodeImage(bytes);
}

Future<Map<String, dynamic>> _cropImageIsolate(
  Map<String, dynamic> args,
) async {
  final img.Image src = args['src'];
  final cropped = img.copyCrop(
    src,
    x: args['x'],
    y: args['y'],
    width: args['w'],
    height: args['h'],
  );
  return {
    'bytes': Uint8List.fromList(img.encodePng(cropped)),
    'width': cropped.width,
    'height': cropped.height,
  };
}

/// Shows the crop modal. Result image can be sent to the results carousel.
/// If [initialImageBytes] is provided, the modal opens with that image loaded.
void showCropModal(BuildContext context, {Uint8List? initialImageBytes}) {
  GlassModal.show(
    context,
    heightFactor: 0.92,
    child: _CropModalContent(initialImageBytes: initialImageBytes),
  );
}

class _CropModalContent extends StatefulWidget {
  final Uint8List? initialImageBytes;

  const _CropModalContent({this.initialImageBytes});

  @override
  State<_CropModalContent> createState() => _CropModalContentState();
}

class _CropModalContentState extends State<_CropModalContent> {
  final _picker = ImagePicker();

  Uint8List? _originalBytes;
  img.Image? _originalImage;

  Uint8List? _croppedBytes;
  int? _croppedW, _croppedH;
  Size? _cropSize;

  // Performance: ValueNotifier prevents full rebuilds during rapid panning
  final ValueNotifier<Offset> _cropOffsetNotifier = ValueNotifier(Offset.zero);

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
    _cropOffsetNotifier.dispose();
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
        _initCrop(decoded);
      });
      await _rebuildCrop();
    } catch (e) {
      _snack('Error loading image: $e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white)),
          backgroundColor: error
              ? const Color(0xFFB00020)
              : const Color(0xFF1B6B49),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _processing = true;
      _originalBytes = null;
      _originalImage = null;
      _croppedBytes = null;
      _cropSize = null;
    });

    try {
      final bytes = await picked.readAsBytes();
      final decoded = await compute(_decodeImageIsolate, bytes);
      if (decoded == null) throw Exception('Unable to decode image');

      setState(() {
        _originalBytes = bytes;
        _originalImage = decoded;
        _initCrop(decoded);
      });

      await _rebuildCrop();
    } catch (e) {
      _snack('Error loading image: $e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _initCrop(img.Image src) {
    const aspect = 9.0 / 20.0;
    final sw = src.width.toDouble();
    final sh = src.height.toDouble();

    double cw = sh * aspect;
    double ch = sh;
    if (cw > sw) {
      cw = sw;
      ch = sw / aspect;
    }
    _cropSize = Size(cw, ch);
    _cropOffsetNotifier.value = Offset((sw - cw) / 2, (sh - ch) / 2);
  }

  Future<void> _rebuildCrop() async {
    final src = _originalImage;
    if (src == null || _cropSize == null) return;

    setState(() => _processing = true);
    try {
      final offset = _cropOffsetNotifier.value;
      final x = offset.dx.round().clamp(0, src.width - 1);
      final y = offset.dy.round().clamp(0, src.height - 1);
      final w = _cropSize!.width.round().clamp(1, src.width - x);
      final h = _cropSize!.height.round().clamp(1, src.height - y);

      final r = await compute(_cropImageIsolate, {
        'src': src,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
      });
      if (!mounted) return;
      setState(() {
        _croppedBytes = r['bytes'];
        _croppedW = r['width'];
        _croppedH = r['height'];
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _sendToResults() {
    if (_sending || _croppedBytes == null) return;

    setState(() => _sending = true);
    try {
      final dataUrl = 'data:image/png;base64,${base64Encode(_croppedBytes!)}';
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
            title: 'Crop Image',
            icon: Icons.crop_rounded,
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
                          imgW: _originalImage?.width.toDouble(),
                          imgH: _originalImage?.height.toDouble(),
                          cropOffsetNotifier: _cropOffsetNotifier,
                          cropSize: _cropSize,
                          onPanEnd: _rebuildCrop,
                          onPickImage: _pickImage,
                          croppedW: _croppedW,
                          croppedH: _croppedH,
                        ),
                      ),
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
    required this.imgW,
    required this.imgH,
    required this.cropOffsetNotifier,
    required this.cropSize,
    required this.onPanEnd,
    required this.onPickImage,
    this.croppedW,
    this.croppedH,
  });

  final bool hasImage;
  final Uint8List? originalBytes;
  final double? imgW;
  final double? imgH;
  final ValueNotifier<Offset> cropOffsetNotifier;
  final Size? cropSize;
  final VoidCallback onPanEnd;
  final VoidCallback onPickImage;
  final int? croppedW;
  final int? croppedH;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: EdgeInsets.zero,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child:
            (!hasImage ||
                originalBytes == null ||
                cropSize == null ||
                imgW == null ||
                imgH == null)
            ? _EmptyViewer(onTap: onPickImage)
            : ClipRRect(
                borderRadius: BorderRadius.circular(_kRadius),
                child: Stack(
                  children: [
                    _CropCanvas(
                      originalBytes: originalBytes!,
                      imgW: imgW!,
                      imgH: imgH!,
                      cropOffsetNotifier: cropOffsetNotifier,
                      cropSize: cropSize!,
                      onPanEnd: onPanEnd,
                      croppedW: croppedW,
                      croppedH: croppedH,
                    ),

                    // Floating Resolution Pill overlay
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            '9:20 Ratio  •  ${croppedW ?? '?'} × ${croppedH ?? '?'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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

class _CropCanvas extends StatelessWidget {
  const _CropCanvas({
    required this.originalBytes,
    required this.imgW,
    required this.imgH,
    required this.cropOffsetNotifier,
    required this.cropSize,
    required this.onPanEnd,
    this.croppedW,
    this.croppedH,
  });

  final Uint8List originalBytes;
  final double imgW;
  final double imgH;
  final ValueNotifier<Offset> cropOffsetNotifier;
  final Size cropSize;
  final VoidCallback onPanEnd;
  final int? croppedW;
  final int? croppedH;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageAspect = imgW / imgH;

        // Bounding the image appropriately (Mimicking BoxFit.contain inside the available space)
        double renderW = constraints.maxWidth;
        double renderH = renderW / imageAspect;
        if (renderH > constraints.maxHeight) {
          renderH = constraints.maxHeight;
          renderW = renderH * imageAspect;
        }

        final scale = renderW / imgW;

        return Center(
          child: SizedBox(
            width: renderW,
            height: renderH,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(originalBytes, fit: BoxFit.fill),
                ),
                // Smooth updates to layout during pan
                ValueListenableBuilder<Offset>(
                  valueListenable: cropOffsetNotifier,
                  builder: (context, offset, child) {
                    final rx = offset.dx * scale;
                    final ry = offset.dy * scale;
                    final rw = cropSize.width * scale;
                    final rh = cropSize.height * scale;

                    return Stack(
                      children: [
                        _dim(top: 0, left: 0, right: 0, height: ry),
                        _dim(top: ry + rh, left: 0, right: 0, bottom: 0),
                        _dim(top: ry, left: 0, width: rx, height: rh),
                        _dim(top: ry, left: rx + rw, right: 0, height: rh),
                        Positioned(
                          top: ry,
                          left: rx,
                          width: rw,
                          height: rh,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (d) {
                              final newX = (offset.dx + d.delta.dx / scale)
                                  .clamp(0.0, imgW - cropSize.width);
                              final newY = (offset.dy + d.delta.dy / scale)
                                  .clamp(0.0, imgH - cropSize.height);
                              cropOffsetNotifier.value = Offset(newX, newY);
                            },
                            onPanEnd: (_) => onPanEnd(),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: _kGreen, width: 2),
                                color: Colors.transparent,
                                boxShadow: [
                                  BoxShadow(
                                    color: _kGreen.withValues(alpha: 0.15),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  ..._corners(),
                                  const Center(
                                    child: Icon(
                                      Icons.open_with_rounded,
                                      color: Colors.white70,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dim({
    double? top,
    double? left,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: Container(color: Colors.black.withValues(alpha: 0.65)),
    );
  }

  List<Widget> _corners() {
    const size = 12.0;
    const w = 2.5;
    return [
      _corner(
        top: 0,
        left: 0,
        borderTop: true,
        borderLeft: true,
        size: size,
        w: w,
      ),
      _corner(
        top: 0,
        right: 0,
        borderTop: true,
        borderRight: true,
        size: size,
        w: w,
      ),
      _corner(
        bottom: 0,
        left: 0,
        borderBottom: true,
        borderLeft: true,
        size: size,
        w: w,
      ),
      _corner(
        bottom: 0,
        right: 0,
        borderBottom: true,
        borderRight: true,
        size: size,
        w: w,
      ),
    ];
  }

  Widget _corner({
    double? top,
    double? left,
    double? right,
    double? bottom,
    bool borderTop = false,
    bool borderLeft = false,
    bool borderRight = false,
    bool borderBottom = false,
    required double size,
    required double w,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CornerPainter(
            color: _kGreen,
            strokeWidth: w,
            top: borderTop,
            left: borderLeft,
            right: borderRight,
            bottom: borderBottom,
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.color,
    required this.strokeWidth,
    this.top = false,
    this.left = false,
    this.right = false,
    this.bottom = false,
  });

  final Color color;
  final double strokeWidth;
  final bool top, left, right, bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    if (top && left) {
      canvas.drawLine(Offset(0, h), const Offset(0, 0), paint);
      canvas.drawLine(const Offset(0, 0), Offset(w, 0), paint);
    } else if (top && right) {
      canvas.drawLine(const Offset(0, 0), Offset(w, 0), paint);
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
    } else if (bottom && left) {
      canvas.drawLine(const Offset(0, 0), Offset(0, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    } else if (bottom && right) {
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
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
