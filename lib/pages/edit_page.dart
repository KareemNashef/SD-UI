import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:sd_companion/elements/widgets/glass_app_bar.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_tab_bar.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// --- ISOLATE HELPER FUNCTIONS ---
Future<img.Image?> _decodeImageIsolate(Uint8List bytes) async {
  return img.decodeImage(bytes);
}

Future<Map<String, dynamic>> _resizeImageIsolate(
  Map<String, dynamic> args,
) async {
  final img.Image src = args['src'];
  final int targetW = args['targetW'];
  final int targetH = args['targetH'];

  final resized = img.copyResize(
    src,
    width: targetW,
    height: targetH,
    interpolation: img.Interpolation.linear,
  );

  final bytes = Uint8List.fromList(img.encodePng(resized));

  return {'bytes': bytes, 'width': resized.width, 'height': resized.height};
}

Future<Map<String, dynamic>> _cropImageIsolate(
  Map<String, dynamic> args,
) async {
  final img.Image src = args['src'];
  final int x = args['x'];
  final int y = args['y'];
  final int w = args['w'];
  final int h = args['h'];

  final cropped = img.copyCrop(src, x: x, y: y, width: w, height: h);
  final bytes = Uint8List.fromList(img.encodePng(cropped));

  return {'bytes': bytes, 'width': cropped.width, 'height': cropped.height};
}

// -----------------------------------------------------------

class EditPage extends StatefulWidget {
  const EditPage({super.key});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  late TabController _tabController;

  // Input Data
  Uint8List? _inputBytes;
  img.Image? _inputImage;

  // Downscale State
  double _downscalePercent = 50;
  Uint8List? _downscaledBytes;
  int? _downscaledWidth;
  int? _downscaledHeight;

  // Crop State
  Uint8List? _croppedBytes;
  int? _croppedWidth;
  int? _croppedHeight;

  // Crop Position Logic
  Offset _cropOffset = Offset.zero;
  Size? _calculatedCropSize;

  // UI State
  bool _isComparingDownscale = false;
  bool _isProcessing = false;
  bool _isSaving = false;

  // NEW: Control tab scrolling physics to prevent conflicts
  ScrollPhysics _tabScrollPhysics = const AlwaysScrollableScrollPhysics();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- SCROLL LOCKING HELPERS ---
  void _lockTabScroll() {
    if (_tabScrollPhysics is! NeverScrollableScrollPhysics) {
      setState(() => _tabScrollPhysics = const NeverScrollableScrollPhysics());
    }
  }

  void _unlockTabScroll() {
    if (_tabScrollPhysics is! AlwaysScrollableScrollPhysics) {
      setState(() => _tabScrollPhysics = const AlwaysScrollableScrollPhysics());
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.red.shade900 : Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile == null) return;

    setState(() {
      _isProcessing = true;
      _clearImageState();
    });

    try {
      final bytes = await File(pickedFile.path).readAsBytes();
      final decoded = await compute(_decodeImageIsolate, bytes);

      if (decoded == null) throw Exception('Unable to decode image');

      setState(() {
        _inputBytes = bytes;
        _inputImage = decoded;
        _resetCropPosition(decoded);
      });

      await _processImages();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error loading image: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _clearImageState() {
    _inputBytes = null;
    _inputImage = null;
    _downscaledBytes = null;
    _downscaledWidth = null;
    _downscaledHeight = null;
    _croppedBytes = null;
    _croppedWidth = null;
    _croppedHeight = null;
    _isComparingDownscale = false;
    _cropOffset = Offset.zero;
  }

  Future<void> _processImages() async {
    await _rebuildDownscale();
    await _rebuildCrop();
  }

  Future<void> _rebuildDownscale() async {
    final src = _inputImage;
    if (src == null) return;

    final p = (_downscalePercent / 100.0).clamp(0.01, 1.0);
    final targetW = (src.width * p).round().clamp(1, src.width);
    final targetH = (src.height * p).round().clamp(1, src.height);

    setState(() => _isProcessing = true);

    try {
      final result = await compute(_resizeImageIsolate, {
        'src': src,
        'targetW': targetW,
        'targetH': targetH,
      });

      if (!mounted) return;
      setState(() {
        _downscaledBytes = result['bytes'];
        _downscaledWidth = result['width'];
        _downscaledHeight = result['height'];
      });
    } catch (e) {
      debugPrint("Error downscaling: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _resetCropPosition(img.Image src) {
    const targetAspect = 9.0 / 20.0;
    final srcW = src.width.toDouble();
    final srcH = src.height.toDouble();

    double cropW = srcH * targetAspect;
    double cropH = srcH;

    if (cropW > srcW) {
      cropW = srcW;
      cropH = srcW / targetAspect;
    }

    _calculatedCropSize = Size(cropW, cropH);
    _cropOffset = Offset((srcW - cropW) / 2, (srcH - cropH) / 2);
  }

  Future<void> _rebuildCrop() async {
    final src = _inputImage;
    if (src == null || _calculatedCropSize == null) return;

    setState(() => _isProcessing = true);

    try {
      final x = _cropOffset.dx.round().clamp(0, src.width - 1);
      final y = _cropOffset.dy.round().clamp(0, src.height - 1);
      final w = _calculatedCropSize!.width.round().clamp(1, src.width - x);
      final h = _calculatedCropSize!.height.round().clamp(1, src.height - y);

      final result = await compute(_cropImageIsolate, {
        'src': src,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
      });

      if (!mounted) return;
      setState(() {
        _croppedBytes = result['bytes'];
        _croppedWidth = result['width'];
        _croppedHeight = result['height'];
      });
    } catch (e) {
      debugPrint("Error cropping: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveCurrentTab() async {
    if (_isSaving || _inputImage == null) return;

    final currentTab = _tabController.index;
    Uint8List? bytesToSave;
    String prefix = "";

    if (currentTab == 0) {
      bytesToSave = _downscaledBytes;
      prefix = "downscaled";
    } else {
      bytesToSave = _croppedBytes;
      prefix = "cropped";
    }

    if (bytesToSave == null) return;

    setState(() => _isSaving = true);

    try {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      if (!status.isGranted) await Permission.photos.request();

      const downloadsPath = '/storage/emulated/0/Download';
      final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('$downloadsPath/$fileName');

      if (await Directory(downloadsPath).exists()) {
        await file.writeAsBytes(bytesToSave);
        _showSnackBar('Saved to Downloads', isError: false);
      } else {
        _showSnackBar('Downloads folder not found', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error saving: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- WIDGET BUILDERS ---

  Widget _buildDownscaleTab() {
    final hasInput = _inputImage != null;
    final displayBytes = _isComparingDownscale ? _inputBytes : _downscaledBytes;

    return Column(
      children: [
        // Image Area with Zoom
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            child: GlassContainer(
              borderRadius: AppTheme.radiusLarge,
              backgroundColor: AppTheme.glassBackground,
              borderColor: AppTheme.glassBorder,
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: hasInput && displayBytes != null
                    // WRAPPER ADDED HERE:
                    ? Listener(
                        onPointerDown: (_) => _lockTabScroll(),
                        onPointerUp: (_) => _unlockTabScroll(),
                        onPointerCancel: (_) => _unlockTabScroll(),
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 5.0,
                          // We don't need onInteractionStart anymore, Listener handles it faster
                          child: Image.memory(
                            displayBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.image,
                          color: Colors.white24,
                          size: 48,
                        ),
                      ),
              ),
            ),
          ),
        ),

        // Controls
        if (hasInput)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassContainer(
              borderRadius: AppTheme.radiusLarge,
              backgroundColor: AppTheme.glassBackground,
              borderColor: AppTheme.glassBorder,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Downscale',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_downscalePercent.toInt()}%',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Colors.amber,
                      inactiveTrackColor: Colors.white10,
                      thumbColor: Colors.white,
                      overlayColor: Colors.amber.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: _downscalePercent,
                      min: 10,
                      max: 100,
                      divisions: 90,
                      label: "${_downscalePercent.toInt()}%",
                      onChanged: (val) =>
                          setState(() => _downscalePercent = val),
                      onChangeEnd: (val) => _rebuildDownscale(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoText(
                          "Original",
                          "${_inputImage?.width}x${_inputImage?.height}",
                        ),
                      ),
                      Expanded(
                        child: _buildInfoText(
                          "Result",
                          "${_downscaledWidth}x${_downscaledHeight}",
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCompareButton(enabled: true),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInteractiveCropArea() {
    if (_inputImage == null || _calculatedCropSize == null)
      return const SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        // ... (calculation logic remains the same: imgW, imgH, scale, rectX, etc.)
        final imgW = _inputImage!.width.toDouble();
        final imgH = _inputImage!.height.toDouble();
        final aspect = imgW / imgH;

        double renderW = constraints.maxWidth;
        double renderH = renderW / aspect;

        if (renderH > constraints.maxHeight) {
          renderH = constraints.maxHeight;
          renderW = renderH * aspect;
        }

        final scale = renderW / imgW;
        final rectX = _cropOffset.dx * scale;
        final rectY = _cropOffset.dy * scale;
        final rectW = _calculatedCropSize!.width * scale;
        final rectH = _calculatedCropSize!.height * scale;
        // ... end calculation logic

        return Center(
          child: SizedBox(
            width: renderW,
            height: renderH,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(_inputBytes!, fit: BoxFit.contain),
                ),
                // Dark Overlays
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: rectY,
                  child: Container(color: Colors.black54),
                ),
                Positioned(
                  top: rectY + rectH,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(color: Colors.black54),
                ),
                Positioned(
                  top: rectY,
                  left: 0,
                  width: rectX,
                  height: rectH,
                  child: Container(color: Colors.black54),
                ),
                Positioned(
                  top: rectY,
                  left: rectX + rectW,
                  right: 0,
                  height: rectH,
                  child: Container(color: Colors.black54),
                ),

                // Draggable Box
                Positioned(
                  top: rectY,
                  left: rectX,
                  width: rectW,
                  height: rectH,
                  // WRAPPER ADDED HERE:
                  child: Listener(
                    onPointerDown: (_) => _lockTabScroll(),
                    onPointerUp: (_) => _unlockTabScroll(),
                    onPointerCancel: (_) => _unlockTabScroll(),
                    child: GestureDetector(
                      behavior:
                          HitTestBehavior.opaque, // Ensures touches are caught
                      onPanUpdate: (details) {
                        setState(() {
                          double newX =
                              _cropOffset.dx + (details.delta.dx / scale);
                          double newY =
                              _cropOffset.dy + (details.delta.dy / scale);
                          newX = newX.clamp(
                            0.0,
                            imgW - _calculatedCropSize!.width,
                          );
                          newY = newY.clamp(
                            0.0,
                            imgH - _calculatedCropSize!.height,
                          );
                          _cropOffset = Offset(newX, newY);
                        });
                      },
                      onPanEnd: (_) => _rebuildCrop(),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.amber, width: 2),
                          color: Colors.transparent,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.crop_free,
                            color: Colors.white54,
                            size: 30,
                          ),
                        ),
                      ),
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

  Widget _buildCropTab() {
    final hasInput = _inputImage != null;
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            child: GlassContainer(
              borderRadius: AppTheme.radiusLarge,
              backgroundColor: AppTheme.glassBackground,
              borderColor: AppTheme.glassBorder,
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: hasInput
                    ? _buildInteractiveCropArea()
                    : const Center(
                        child: Icon(
                          Icons.crop,
                          color: Colors.white24,
                          size: 48,
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (hasInput)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassContainer(
              borderRadius: AppTheme.radiusLarge,
              backgroundColor: AppTheme.glassBackground,
              borderColor: AppTheme.glassBorder,
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoText("Crop Aspect", "9:20"),
                  Container(width: 1, height: 20, color: Colors.white10),
                  _buildInfoText(
                    "Result",
                    "${_croppedWidth}x${_croppedHeight}",
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoText(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCompareButton({required bool enabled}) {
    return GestureDetector(
      onTapDown: enabled
          ? (_) => setState(() => _isComparingDownscale = true)
          : null,
      onTapUp: (_) => setState(() => _isComparingDownscale = false),
      onTapCancel: () => setState(() => _isComparingDownscale = false),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _isComparingDownscale
              ? Colors.amber.withOpacity(0.2)
              : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isComparingDownscale ? Colors.amber : Colors.white24,
          ),
        ),
        child: Center(
          child: Text(
            _isComparingDownscale ? 'Showing Original' : 'Hold to Compare',
            style: TextStyle(
              color: _isComparingDownscale ? Colors.amber : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControlBar(bool hasInput) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
      child: GlassContainer(
        borderRadius: AppTheme.radiusLarge,
        backgroundColor: AppTheme.glassBackground,
        borderColor: AppTheme.glassBorder,
        padding: const EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12,
        ), // Extra bottom padding for safe area
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Clear / New Button
            if (hasInput)
              _buildBottomBtn(
                Icons.close,
                "Clear",
                Colors.redAccent,
                () => _clearImageState(),
              ),

            // Add Photo Button
            _buildBottomBtn(
              Icons.add_photo_alternate,
              hasInput ? "New" : "Add Photo",
              Colors.amber,
              _pickImage,
            ),

            // Save Button
            if (hasInput)
              _buildBottomBtn(
                Icons.save_alt,
                "Save",
                Colors.greenAccent,
                _saveCurrentTab,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasInput = _inputImage != null;

    return Scaffold(
      backgroundColor: Colors.black, // Dark background behind glass
      body: Stack(
        children: [
          // Background content could go here
          Column(
            children: [
              // 1. App Bar
              const GlassAppBar(title: 'Image Editor'),

              const SizedBox(height: 16),

              // 2. Tab Bar
              if (hasInput)
                GlassTabBar(
                  controller: _tabController,
                  tabs: const ['Downscale', 'Crop'],
                ),

              // 3. Main Content
              Expanded(
                child: hasInput
                    ? TabBarView(
                        controller: _tabController,
                        physics:
                            _tabScrollPhysics, // Apply the physics variable
                        children: [_buildDownscaleTab(), _buildCropTab()],
                      )
                    : Center(
                        child: Text(
                          'Select an image to start',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ),
              ),

              // 4. Bottom Controls
              _buildBottomControlBar(hasInput),
            ],
          ),

          // Loading Overlay
          if (_isProcessing || _isSaving)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              ),
            ),
        ],
      ),
    );
  }
}
