// ==================== Image Upload Container ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// Local imports - Elements
import 'package:sd_companion/elements/canvas/canvas_gesture.dart';
import 'package:sd_companion/elements/canvas/mask_painter.dart';
import 'package:sd_companion/elements/canvas/zoom_preview_widget.dart';
import 'package:sd_companion/elements/modals/checkpoint_test_modal.dart';
import 'package:sd_companion/elements/modals/history_modal.dart';
import 'package:sd_companion/elements/modals/lora_modal.dart';
import 'package:sd_companion/elements/widgets/glass_action_buttons.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/backend/a1111_backend.dart';
import 'package:sd_companion/logic/drawing/drawing_coordinates.dart';
import 'package:sd_companion/logic/drawing/mask_generator.dart';
import 'package:sd_companion/logic/generation_logic.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/image/image_processor.dart';
import 'package:sd_companion/logic/models/drawing_models.dart';
import 'package:sd_companion/logic/services/checkpoint_testing_service.dart';
import 'package:sd_companion/logic/services/progress_service.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';
import 'package:sd_companion/logic/utils/test_mode.dart';

// Image Upload Container Implementation

class ImageContainer extends StatefulWidget {
  final Function(Uint8List?)? onMaskGenerated;

  const ImageContainer({super.key, this.onMaskGenerated});

  @override
  State<ImageContainer> createState() => _ImageContainerState();
}

class _ImageContainerState extends State<ImageContainer> {
  // ===== Class Variables ===== //

  // Image Variables
  File? _imageFile;
  ui.Image? _decodedImage;
  final ImagePicker _picker = ImagePicker();

  // Drawing Variables
  DrawingMode _currentMode = DrawingMode.draw;
  List<DrawingPath> _paths = [];
  List<DrawingPoint> _currentPathPoints = [];
  final List<List<DrawingPath>> _undoHistory = [];
  double _strokeWidth = 20.0;
  bool _isDrawing = false;

  // Outpainting Variables
  bool _isOutpaintingMode = false;
  String? _activeDragHandle; // Tracks which handle is being dragged
  double _padLeft = 0;
  double _padRight = 0;
  double _padTop = 0;
  double _padBottom = 0;

  // Prompt Variables
  bool _isOptimizingPrompt = false;
  String? _previousPrompt;

  // Pan Variables
  Offset? _currentPanLocalPosition;
  Size? _canvasRenderedSize;

  // Controller
  final userPrompt = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();

  // Checkpoint Testing
  final CheckpointTestingService _checkpointTestingService = CheckpointTestingService();

  // Stitch Variables
  final List<File> _stitchImages = [];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    globalImageToEdit.addListener(_onEditImageRequest);
    globalSelectedLoras.addListener(_onLoraStateChanged);
    globalSelectedLoraTags.addListener(_onLoraStateChanged);
  }

  @override
  void dispose() {
    userPrompt.dispose();
    _promptFocusNode.dispose();
    globalImageToEdit.removeListener(_onEditImageRequest);
    globalSelectedLoras.removeListener(_onLoraStateChanged);
    globalSelectedLoraTags.removeListener(_onLoraStateChanged);
    super.dispose();
  }

  void _onLoraStateChanged() {
    if (mounted) setState(() {});
  }

  // ===== Class Functions ===== //

  Future<void> _onEditImageRequest() async {
    final imageUrl = globalImageToEdit.value;
    if (imageUrl == null || !mounted) return;
    globalImageToEdit.value = null;
    await _loadImageFromUrl(imageUrl);
  }

  Future<void> _loadImageFromUrl(String url) async {
    try {
      Uint8List imageBytes;
      if (url.startsWith('data:image/')) {
        final commaIndex = url.indexOf(',');
        if (commaIndex != -1) {
          imageBytes = base64Decode(url.substring(commaIndex + 1));
        } else {
          throw Exception('Invalid base64 data URL');
        }
      } else {
        imageBytes = await fetchImageBytes(url);
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(tempPath);
      await file.writeAsBytes(imageBytes);
      final ui.Image image = await decodeImageFromList(imageBytes);

      setState(() {
        _imageFile = file;
        _decodedImage = image;
        _paths.clear();
        _undoHistory.clear();
        _resetOutpainting();
      });

      globalInputImage.value = file;
    } catch (e) {
      if (mounted) _showError('Error loading image: $e');
    }
  }

  void _showModelSelectionDialog() {
    final TextEditingController modelController = TextEditingController(text: globalRouterModel.value);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppTheme.glassBorder),
          ),
          title: const Text(
            "OpenRouter Model",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Enter the model ID from OpenRouter", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
              const SizedBox(height: 16),
              GlassInput(controller: modelController, hintText: "arcee-ai/trinity-large-preview:free", prefixIcon: Icons.model_training),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            ),
            ElevatedButton(
              onPressed: () {
                globalRouterModel.value = modelController.text;
                StorageService.saveRouterModel();
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Optimization model updated"), backgroundColor: AppTheme.accentPrimary, behavior: SnackBarBehavior.floating));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                "Save",
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final ui.Image image = await decodeImageFromList(bytes);

      setState(() {
        _imageFile = file;
        _decodedImage = image;
        _paths.clear();
        _undoHistory.clear();
        _resetOutpainting();
      });

      globalInputImage.value = file;
    }
  }

  void _resetImage() {
    setState(() {
      _imageFile = null;
      _decodedImage = null;
      _paths.clear();
      _undoHistory.clear();
      _resetOutpainting();
    });
    globalInputImage.value = null;
  }

  void _resetOutpainting() {
    _padLeft = 0;
    _padRight = 0;
    _padTop = 0;
    _padBottom = 0;
    _activeDragHandle = null;
  }

  // ===== Drawing Logic ===== //

  void _onPanStart(DragStartDetails details, Size containerSize) {
    if (_imageFile == null) return;
    setState(() {
      _isDrawing = true;
      _currentPathPoints = [];
      _undoHistory.add(List<DrawingPath>.from(_paths.map((p) => DrawingPath(points: p.points, mode: p.mode, strokeWidth: p.strokeWidth))));
    });
    _addPointToCurrentPath(details.localPosition, containerSize);
  }

  void _onPanUpdate(DragUpdateDetails details, Size containerSize) {
    if (!_isDrawing) return;
    _addPointToCurrentPath(details.localPosition, containerSize);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDrawing) return;
    setState(() {
      if (_currentPathPoints.isNotEmpty) {
        _paths.add(DrawingPath(points: List.from(_currentPathPoints), mode: _currentMode, strokeWidth: _strokeWidth));
      }
      _currentPathPoints.clear();
      _isDrawing = false;
      _currentPanLocalPosition = null;
    });
  }

  void _addPointToCurrentPath(Offset localPosition, Size containerSize) {
    if (_decodedImage == null) return;
    _canvasRenderedSize = containerSize;

    final imagePoint = convertScreenToImageCoordinates(localPosition: localPosition, containerSize: containerSize, decodedImage: _decodedImage!);

    _currentPanLocalPosition = localPosition;
    setState(() {
      _currentPathPoints.add(DrawingPoint(point: imagePoint));
    });
  }

  void _undo() {
    if (_undoHistory.isNotEmpty) {
      setState(() => _paths = _undoHistory.removeLast());
    }
  }

  void _clearMask() {
    setState(() {
      _undoHistory.add(List.from(_paths));
      _paths.clear();
    });
  }

  // ===== Mask Generation Logic ===== //

  Future<Uint8List?> _generateDrawingMask() async {
    if (_decodedImage == null || _canvasRenderedSize == null) return null;
    return await generateDrawingMask(decodedImage: _decodedImage!, paths: _paths, canvasRenderedSize: _canvasRenderedSize!);
  }

  Future<List<Uint8List>> _generateOutpaintData() async {
    if (_decodedImage == null) return [];
    return await generateOutpaintData(decodedImage: _decodedImage!, padLeft: _padLeft, padRight: _padRight, padTop: _padTop, padBottom: _padBottom);
  }

  // ===== Generation Logic ===== //

  Future<void> generateImage() async {
    if (_imageFile == null || _decodedImage == null) {
      _showError('Please select an image first');
      return;
    }

    await checkServerStatus();
    if (!globalServerStatus.value) {
      _showError('Server not connected');
      return;
    }

    try {
      ProgressService().startProgressPolling();
      navigateToResultsPage();

      Uint8List imageBytesToUse;
      Uint8List maskBytesToUse;

      if (_isOutpaintingMode) {
        final data = await _generateOutpaintData();
        if (data.isEmpty) throw Exception("Failed to generate outpaint data");
        imageBytesToUse = data[0];
        maskBytesToUse = data[1];
      } else {
        imageBytesToUse = await _imageFile!.readAsBytes();
        final generatedMask = await _generateDrawingMask();
        if (generatedMask == null) {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, _decodedImage!.width.toDouble(), _decodedImage!.height.toDouble()), Paint()..color = Colors.black);
          final img = await recorder.endRecording().toImage(_decodedImage!.width, _decodedImage!.height);
          maskBytesToUse = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        } else {
          maskBytesToUse = generatedMask;
        }
      }

      final loraStrings = GenerationLogic.buildLoraPromptAddition(
        globalSelectedLoras.value,
        globalSelectedLoraTags.value,
      );

      // Encode stitch images to base64 if any
      List<String>? stitchBase64;
      if (_stitchImages.isNotEmpty) {
        stitchBase64 = [];
        for (final file in _stitchImages) {
          final bytes = await file.readAsBytes();
          stitchBase64.add(base64Encode(bytes));
        }
      }

      final newImages = await GenerationLogic.generateImg2Img(prompt: userPrompt.text, imageBytes: imageBytesToUse, maskBytes: maskBytesToUse, loraPromptAdditions: loraStrings, stitchImages: stitchBase64);

      final currentImages = Set<String>.from(globalResultImages.value);
      currentImages.addAll(newImages);
      globalResultImages.value = currentImages;

      ProgressService().stopProgressPolling();
    } catch (e) {
      ProgressService().stopProgressPolling();
      if (mounted) _showError('Error generating image: ${e.toString()}');
    }
  }

  // ===== Testing Logic ===== //

  Future<void> _startCheckpointTesting(List<String> checkpoints) async {
    if (_imageFile == null) {
      _showError('Please select an image first');
      return;
    }
    await _checkpointTestingService.startCheckpointTesting(checkpoints: checkpoints, onGenerate: generateImage);
  }

  Future<void> _startSamplerTesting(List<String> samplers, String target) async {
    await _checkpointTestingService.startSamplerTesting(samplers: samplers, targetCheckpoint: target, onGenerate: generateImage);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  // ===== Class Widgets ===== //

  Widget _buildUploadPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade900,
              border: Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.3), width: 2),
              boxShadow: [BoxShadow(color: AppTheme.accentPrimary.withValues(alpha: 0.2), blurRadius: 24, spreadRadius: 4)],
            ),
            child: Icon(Icons.cloud_upload_rounded, size: 56, color: AppTheme.accentPrimary.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to Upload Image',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWithOutpainting() {
    if (_decodedImage == null) return const SizedBox();

    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();

    final totalW = imgW + _padLeft + _padRight;
    final totalH = imgH + _padTop + _padBottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Reduced Zoom Factor: 2.0x instead of 3.0x
        final virtualW = math.max(totalW, imgW * 2.0);
        final virtualH = math.max(totalH, imgH * 2.0);

        final scaleX = constraints.maxWidth / virtualW;
        final scaleY = constraints.maxHeight / virtualH;
        final scale = math.min(scaleX, scaleY);

        final displayW = totalW * scale;
        final displayH = totalH * scale;

        return Center(
          child: Container(
            width: displayW,
            height: displayH,
            decoration: BoxDecoration(
              color: Colors.black45,
              border: Border.all(color: Colors.white10, width: 1),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Grid Pattern
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.1,
                    child: Image.asset(
                      'assets/grid_pattern.png',
                      repeat: ImageRepeat.repeat,
                      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ),

                // 2. Original Image
                Positioned(
                  left: _padLeft * scale,
                  top: _padTop * scale,
                  width: imgW * scale,
                  height: imgH * scale,
                  child: Container(
                    decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]),
                    child: Image.file(_imageFile!, fit: BoxFit.fill),
                  ),
                ),

                // 3. Drag Handles (Now using AlwaysWinPanGestureRecognizer)
                _buildDragHandle(
                  handleId: 'top',
                  top: -15,
                  left: 0,
                  right: 0,
                  height: 30,
                  cursor: SystemMouseCursors.resizeUpDown,
                  icon: Icons.drag_handle,
                  isHorizontal: true,
                  onDrag: (delta) {
                    setState(() {
                      _padTop = math.max(0, _padTop - (delta.dy / scale));
                    });
                  },
                ),
                _buildDragHandle(
                  handleId: 'bottom',
                  bottom: -15,
                  left: 0,
                  right: 0,
                  height: 30,
                  cursor: SystemMouseCursors.resizeUpDown,
                  icon: Icons.drag_handle,
                  isHorizontal: true,
                  onDrag: (delta) {
                    setState(() {
                      _padBottom = math.max(0, _padBottom + (delta.dy / scale));
                    });
                  },
                ),
                _buildDragHandle(
                  handleId: 'left',
                  top: 0,
                  bottom: 0,
                  left: -15,
                  width: 30,
                  cursor: SystemMouseCursors.resizeLeftRight,
                  icon: Icons.drag_handle,
                  isHorizontal: false,
                  onDrag: (delta) {
                    setState(() {
                      _padLeft = math.max(0, _padLeft - (delta.dx / scale));
                    });
                  },
                ),
                _buildDragHandle(
                  handleId: 'right',
                  top: 0,
                  bottom: 0,
                  right: -15,
                  width: 30,
                  cursor: SystemMouseCursors.resizeLeftRight,
                  icon: Icons.drag_handle,
                  isHorizontal: false,
                  onDrag: (delta) {
                    setState(() {
                      _padRight = math.max(0, _padRight + (delta.dx / scale));
                    });
                  },
                ),

                // 4. Size Indicator
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text("${totalW.toInt()} x ${totalH.toInt()}", style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDragHandle({required String handleId, double? top, double? bottom, double? left, double? right, double? width, double? height, required MouseCursor cursor, required IconData icon, required bool isHorizontal, required Function(Offset) onDrag}) {
    final bool isActive = _activeDragHandle == handleId;

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            AlwaysWinPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<AlwaysWinPanGestureRecognizer>(() => AlwaysWinPanGestureRecognizer(), (AlwaysWinPanGestureRecognizer instance) {
              instance
                ..onStart = (_) {
                  setState(() {
                    _activeDragHandle = handleId;
                  });
                }
                ..onUpdate = (DragUpdateDetails details) {
                  onDrag(details.delta);
                }
                ..onEnd = (_) {
                  setState(() {
                    _activeDragHandle = null;
                  });
                };
            }),
          },
          child: Container(
            decoration: BoxDecoration(color: Colors.cyan.withValues(alpha: 0.0)),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: isHorizontal ? 40 : 16,
                height: isHorizontal ? 16 : 40,
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.warning : AppTheme.accentPrimary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isActive ? Colors.white : Colors.white70, width: isActive ? 2.0 : 1.5),
                  boxShadow: [BoxShadow(color: isActive ? AppTheme.warning.withValues(alpha: 0.4) : Colors.black26, blurRadius: isActive ? 8 : 4)],
                ),
                child: Icon(isHorizontal ? Icons.height : Icons.width_normal, color: isActive ? Colors.black87 : Colors.white, size: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageWithDrawing() {
    final imageSize = Size(_decodedImage!.width.toDouble(), _decodedImage!.height.toDouble());
    final containerSize = _canvasRenderedSize ?? Size.zero;
    final imageAspectRatio = imageSize.width / imageSize.height;
    final containerAspectRatio = containerSize.width / containerSize.height;

    late final Rect displayRect;
    if (imageAspectRatio > containerAspectRatio) {
      final h = containerSize.width / imageAspectRatio;
      displayRect = Rect.fromLTWH(0, (containerSize.height - h) / 2, containerSize.width, h);
    } else {
      final w = containerSize.height * imageAspectRatio;
      displayRect = Rect.fromLTWH((containerSize.width - w) / 2, 0, w, containerSize.height);
    }

    final double calculatedZoomFactor = 1.0 + (100.0 - _strokeWidth) / 100.0 * 3.0;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasRenderedSize = constraints.biggest;
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                child: RawGestureDetector(
                  gestures: <Type, GestureRecognizerFactory>{
                    AlwaysWinPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<AlwaysWinPanGestureRecognizer>(() => AlwaysWinPanGestureRecognizer(), (AlwaysWinPanGestureRecognizer instance) {
                      instance
                        ..onStart = (DragStartDetails details) {
                          _onPanStart(details, constraints.biggest);
                        }
                        ..onUpdate = (DragUpdateDetails details) {
                          _onPanUpdate(details, constraints.biggest);
                        }
                        ..onEnd = (DragEndDetails details) {
                          _onPanEnd(details);
                        };
                    }),
                  },
                  child: Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      Positioned.fill(child: Image.file(_imageFile!, fit: BoxFit.contain)),
                      if (_decodedImage != null)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: MaskPainter(
                              paths: [
                                ..._paths,
                                if (_currentPathPoints.isNotEmpty) DrawingPath(points: _currentPathPoints, mode: _currentMode, strokeWidth: _strokeWidth),
                              ],
                              imageSize: imageSize,
                              containerSize: constraints.biggest,
                            ),
                          ),
                        ),
                      if (_isDrawing && _currentPanLocalPosition != null && _canvasRenderedSize != null)
                        Positioned(
                          left: 16,
                          top: 16,
                          child: IgnorePointer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: ZoomPreviewWidget(decodedImage: _decodedImage!, allPaths: _paths, currentPath: _currentPathPoints, currentDrawingMode: _currentMode, strokeWidth: _strokeWidth, currentDrawingPoint: _currentPanLocalPosition!, originalCanvasSize: _canvasRenderedSize!, zoomFactor: calculatedZoomFactor, displayRect: displayRect),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 40,
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.all(3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [_buildModeButton(DrawingMode.draw, Icons.brush_rounded), const SizedBox(width: 2), _buildModeButton(DrawingMode.erase, Icons.auto_fix_high_rounded)]),
                  ),
                  const SizedBox(width: 8),
                  _buildActionIcon(icon: Icons.undo_rounded, onPressed: _undoHistory.isNotEmpty ? _undo : null, tooltip: "Undo"),
                  const SizedBox(width: 8),
                  _buildActionIcon(icon: Icons.layers_clear_rounded, onPressed: _paths.isNotEmpty ? _clearMask : null, tooltip: "Clear Mask"),
                  const SizedBox(width: 8),
                  _buildActionIcon(icon: Icons.restart_alt_rounded, onPressed: _resetImage, tooltip: "Reset All", isDestructive: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                    child: Icon(Icons.circle, size: _strokeWidth.clamp(4, 20).toDouble(), color: AppTheme.accentPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 20,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(activeTrackColor: AppTheme.accentPrimary, inactiveTrackColor: Colors.white.withValues(alpha: 0.1), thumbColor: Colors.white, trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 2), overlayShape: const RoundSliderOverlayShape(overlayRadius: 16)),
                        child: Slider(value: _strokeWidth, min: 1.0, max: 100.0, onChanged: (value) => setState(() => _strokeWidth = value)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      "${_strokeWidth.round()}px",
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeButton(DrawingMode mode, IconData icon) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _currentMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: isSelected ? AppTheme.accentPrimary : Colors.transparent, borderRadius: BorderRadius.circular(AppTheme.radiusSmall), boxShadow: isSelected ? AppTheme.glowPrimary(intensity: 0.2) : []),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.white24)],
        ),
      ),
    );
  }

  Widget _buildActionIcon({required IconData icon, required VoidCallback? onPressed, String? tooltip, bool isDestructive = false}) {
    final isDisabled = onPressed == null;
    return Tooltip(
      message: tooltip ?? '',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isDisabled ? 0.3 : 1.0,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDestructive && !isDisabled ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
              border: Border.all(color: isDestructive && !isDisabled ? AppTheme.error.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05)),
            ),
            child: Icon(icon, size: 18, color: isDestructive && !isDisabled ? AppTheme.error : Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasEditor() {
    final hasImage = _imageFile != null;
    const accentColor = AppTheme.accentPrimary;

    return GestureDetector(
      onTap: hasImage ? null : _pickImage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 550,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: hasImage ? accentColor.withValues(alpha: 0.3) : AppTheme.glassBorder, width: hasImage ? 2 : 1),
          boxShadow: hasImage ? [BoxShadow(color: accentColor.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: -5)] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Content
              hasImage ? (_isOutpaintingMode ? _buildImageWithOutpainting() : _buildImageWithDrawing()) : _buildUploadPrompt(),

              // Floating Toggle (Only show if image exists)
              if (hasImage) Positioned(top: 16, right: 16, child: _buildModeToggle()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    // Fixed dimensions ensure the sliding math works perfectly
    const double itemWidth = 50.0;
    const double itemHeight = 36.0;
    const double padding = 4.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Container(
        // Calculate total width based on items + padding
        width: (itemWidth * 2) + (padding * 2) + 2,
        height: itemHeight + (padding * 2),
        padding: const EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Stack(
          children: [
            // 1. The Sliding Pill Indicator
            AnimatedAlign(
              alignment: _isOutpaintingMode ? Alignment.centerRight : Alignment.centerLeft,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutQuart,
              child: Container(
                width: itemWidth,
                height: itemHeight,
                decoration: BoxDecoration(
                  color: AppTheme.accentPrimary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppTheme.accentPrimary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 2))],
                ),
              ),
            ),

            // 2. The Icons (Foreground)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToggleItem(icon: Icons.brush_rounded, isActive: !_isOutpaintingMode, onTap: () => setState(() => _isOutpaintingMode = false), tooltip: "Inpaint (Brush)", width: itemWidth, height: itemHeight),
                _buildToggleItem(icon: Icons.aspect_ratio_rounded, isActive: _isOutpaintingMode, onTap: () => setState(() => _isOutpaintingMode = true), tooltip: "Outpaint (Resize)", width: itemWidth, height: itemHeight),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem({required IconData icon, required bool isActive, required VoidCallback onTap, required String tooltip, required double width, required double height}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque, // Ensures the empty space is clickable
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              // Icon color transitions: Black when Active (on pill), White when Inactive
              child: Icon(icon, size: 20, color: isActive ? Colors.black : Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptSection() {
    final bool hasText = userPrompt.text.isNotEmpty;
    final bool canUndo = _previousPrompt != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(4.0, 0.0, 4.0, 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Section Title
              Row(
                children: [
                  const Icon(Icons.dashboard_customize_rounded, color: AppTheme.accentPrimary, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "PROMPT",
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.2),
                  ),
                ],
              ),

              // Modern Action Toolbar
              if (hasText)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Undo Button (Icon Only)
                    if (canUndo) ...[
                      Tooltip(
                        message: "Undo",
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              userPrompt.text = _previousPrompt!;
                              userPrompt.selection = TextSelection.fromPosition(TextPosition(offset: userPrompt.text.length));
                              _previousPrompt = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Icon(Icons.undo_rounded, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],

                    // 2. AI Optimize Button (Sleek Pill Style)
                    Tooltip(
                      message: "Long press to select model",
                      child: InkWell(
                        onLongPress: _showModelSelectionDialog,
                        onTap: _isOptimizingPrompt
                            ? null
                            : () async {
                                setState(() {
                                  _isOptimizingPrompt = true;
                                  _previousPrompt = userPrompt.text;
                                });
                                try {
                                  final optimizeResult = await A1111Backend().optimizePrompt(userPrompt.text, globalCheckpointDataMap[globalCurrentCheckpointName]?.baseModel, openRouterModel: globalRouterModel.value);
                                  if (mounted) {
                                    setState(() {
                                      userPrompt.text = optimizeResult;
                                      userPrompt.selection = TextSelection.fromPosition(TextPosition(offset: userPrompt.text.length));
                                    });
                                  }
                                } catch (e) {
                                  if (mounted) _showError("Optimization failed: $e");
                                } finally {
                                  if (mounted) setState(() => _isOptimizingPrompt = false);
                                }
                              },
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.accentPrimary.withValues(alpha: 0.1),
                            border: Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.3), width: 1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              if (_isOptimizingPrompt) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentPrimary)) else const Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.accentPrimary),
                              const SizedBox(width: 6),
                              Text(
                                _isOptimizingPrompt ? "Optimizing..." : "Optimize",
                                style: const TextStyle(color: AppTheme.accentPrimary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // 3. Clear Button (Icon Only)
                    Tooltip(
                      message: "Clear",
                      child: InkWell(
                        onTap: () => setState(() => userPrompt.clear()),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Icon(Icons.close_rounded, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Text Field Container
        GlassInput(controller: userPrompt, hintText: 'Imagine a futuristic city with glowing neon lights...', maxLines: 3, onChanged: (_) => setState(() {})),
      ],
    );
  }

  // ===== Stitch Image Helpers ===== //

  Future<void> _pickStitchImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _stitchImages.add(File(pickedFile.path)));
    }
  }

  void _removeStitchImage(int index) {
    setState(() => _stitchImages.removeAt(index));
  }

  // ===== Stitch Section Widget ===== //

  Widget _buildStitchSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header row
          Padding(
            padding: const EdgeInsets.fromLTRB(4.0, 0.0, 4.0, 8.0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_mosaic_rounded, color: AppTheme.accentPrimary, size: 16),
                const SizedBox(width: 6),
                Text(
                  "IMAGE STITCH",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.2),
                ),
                const Spacer(),
                if (_stitchImages.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppTheme.accentPrimary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '${_stitchImages.length}',
                      style: const TextStyle(color: AppTheme.accentPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          // Stitch image strip
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: _stitchImages.isNotEmpty ? AppTheme.accentPrimary.withValues(alpha: 0.25) : AppTheme.glassBorder),
            ),
            padding: const EdgeInsets.all(12),
            child: _stitchImages.isEmpty
                ? // Empty state — just the add button
                  GestureDetector(
                    onTap: _pickStitchImage,
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.03),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, color: Colors.white.withValues(alpha: 0.4), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              "Add images to stitch",
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : // Populated state — thumbnails + add button
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _stitchImages.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        // Last item is always the "add" tile
                        if (index == _stitchImages.length) {
                          return GestureDetector(
                            onTap: _pickStitchImage,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.5),
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.white.withValues(alpha: 0.03),
                              ),
                              child: Icon(Icons.add_rounded, color: Colors.white.withValues(alpha: 0.4), size: 28),
                            ),
                          );
                        }

                        // Thumbnail tile with remove badge
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(_stitchImages[index], width: 72, height: 72, fit: BoxFit.cover),
                            ),
                            // Remove badge
                            Positioned(
                              top: -6,
                              right: -6,
                              child: GestureDetector(
                                onTap: () => _removeStitchImage(index),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppTheme.error,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black, width: 2),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
                                  ),
                                  child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Utility Cluster
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassOptionButton(
              icon: Icons.science_outlined,
              tooltip: 'Test Lab',
              onTap: () {
                FocusScope.of(context).unfocus();
                showCheckpointTesterModal(context, (mode, items) {
                  if (mode == TestMode.checkpoints) {
                    _startCheckpointTesting(items);
                  } else {
                    _startSamplerTesting(items, globalCurrentCheckpointName);
                  }
                });
              },
            ),
            const SizedBox(width: 4),
            GlassOptionButton(
              icon: Icons.auto_awesome_mosaic_outlined,
              tooltip: 'LoRAs',
              onTap: () {
                FocusScope.of(context).unfocus();
                showLorasModal(
                  context,
                  globalSelectedLoras.value,
                  globalSelectedLoraTags.value,
                  (newLoras, newTags) {
                    globalSelectedLoras.value = Map.from(newLoras);
                    globalSelectedLoraTags.value = Map.from(newTags);
                  },
                );
              },
            ),
            const SizedBox(width: 4),
            GlassOptionButton(
              icon: Icons.bookmark_border_rounded,
              tooltip: 'Prompt Vault',
              onTap: () {
                FocusScope.of(context).unfocus();
                showInpaintHistory(context, (selectedItem) {
                  setState(() {
                    userPrompt.text = selectedItem;
                    userPrompt.selection = TextSelection.fromPosition(TextPosition(offset: userPrompt.text.length));
                  });
                });
              },
            ),
          ],
        ),

        const SizedBox(width: 12),

        // Main Generate Button
        Expanded(
          child: GlassGenButton(
            onTap: () {
              FocusScope.of(context).unfocus();
              if (userPrompt.text.isNotEmpty) {
                setState(() {
                  globalInpaintHistory.add(userPrompt.text);
                  StorageService.saveInpaintHistory();
                });
                generateImage();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("Please enter a prompt first"), backgroundColor: AppTheme.glassBackgroundDark, behavior: SnackBarBehavior.floating));
              }
            },
          ),
        ),
      ],
    );
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildCanvasEditor(),
            const SizedBox(height: 24),
            _buildPromptSection(),
            const SizedBox(height: 16),
            _buildStitchSection(),
            const SizedBox(height: 16),
            _buildControlBar(),
            const SizedBox(height: 16), // Bottom padding
          ],
        ),
      ),
    );
  }
}
