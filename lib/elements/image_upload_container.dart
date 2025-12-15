// ==================== Image Container ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// Local imports - Logic
import 'package:sd_companion/logic/drawing_models.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/progress_service.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/generation_logic.dart';

// Local imports - Elements
import 'package:sd_companion/elements/mask_painter.dart';
import 'package:sd_companion/elements/zoom_preview_widget.dart';
import 'package:sd_companion/elements/canvas_gesture.dart';
import 'package:sd_companion/elements/action_buttons.dart';
import 'package:sd_companion/elements/history_modal.dart';
import 'package:sd_companion/elements/checkpoint_modal.dart';
import 'package:sd_companion/elements/lora_modal.dart';

// ========== Image Container Class ========== //

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
  List<List<DrawingPath>> _undoHistory = [];
  double _strokeWidth = 20.0;
  bool _isDrawing = false;

  // Pan Variables
  Offset? _currentPanLocalPosition;
  Size? _canvasRenderedSize;

  // Controller
  final userPrompt = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();

  // Checkpoint Testing
  bool _isCheckpointTesting = false;
  CheckpointData? _originalConfig;

  // Lora Variables
  Map<String, double> _selectedLoras = {};
  Map<String, Set<String>> _selectedLoraTags = {};

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    globalImageToEdit.addListener(_onEditImageRequest);
  }

  @override
  void dispose() {
    userPrompt.dispose();
    _promptFocusNode.dispose();
    globalImageToEdit.removeListener(_onEditImageRequest);
    super.dispose();
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
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        } else {
          throw Exception('Failed: ${response.statusCode}');
        }
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(tempPath);
      await file.writeAsBytes(imageBytes);
      final ui.Image image = await decodeImageFromList(imageBytes);

      setState(() {
        _imageFile = file;
        _decodedImage = image;
        _paths.clear();
        _undoHistory.clear();
      });
    } catch (e) {
      if (mounted) _showError('Error loading image: $e');
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final ui.Image image = await decodeImageFromList(bytes);

      setState(() {
        _imageFile = file;
        _decodedImage = image;
        _paths.clear();
        _undoHistory.clear();
      });
    }
  }

  void _resetImage() {
    setState(() {
      _imageFile = null;
      _decodedImage = null;
      _paths.clear();
      _undoHistory.clear();
    });
  }

  // --- Drawing Logic ---

  void _onPanStart(DragStartDetails details, Size containerSize) {
    if (_imageFile == null) return;
    setState(() {
      _isDrawing = true;
      _currentPathPoints = [];
      _undoHistory.add(
        List<DrawingPath>.from(
          _paths.map(
            (p) => DrawingPath(
              points: p.points,
              mode: p.mode,
              strokeWidth: p.strokeWidth,
            ),
          ),
        ),
      );
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
        _paths.add(
          DrawingPath(
            points: List.from(_currentPathPoints),
            mode: _currentMode,
            strokeWidth: _strokeWidth,
          ),
        );
      }
      _currentPathPoints.clear();
      _isDrawing = false;
      _currentPanLocalPosition = null;
    });
  }

  void _addPointToCurrentPath(Offset localPosition, Size containerSize) {
    if (_decodedImage == null) return;
    _canvasRenderedSize = containerSize;

    final imageSize = Size(
      _decodedImage!.width.toDouble(),
      _decodedImage!.height.toDouble(),
    );
    final imageAspectRatio = imageSize.width / imageSize.height;
    final containerAspectRatio = containerSize.width / containerSize.height;

    // Calculate display metrics
    late final Size displaySize;
    late final Offset displayOffset;

    if (imageAspectRatio > containerAspectRatio) {
      displaySize = Size(
        containerSize.width,
        containerSize.width / imageAspectRatio,
      );
      displayOffset = Offset(
        0,
        (containerSize.height - displaySize.height) / 2,
      );
    } else {
      displaySize = Size(
        containerSize.height * imageAspectRatio,
        containerSize.height,
      );
      displayOffset = Offset((containerSize.width - displaySize.width) / 2, 0);
    }

    final imageRect = Rect.fromLTWH(
      displayOffset.dx,
      displayOffset.dy,
      displaySize.width,
      displaySize.height,
    );

    if (!imageRect.contains(localPosition)) {
      localPosition = Offset(
        localPosition.dx.clamp(imageRect.left, imageRect.right),
        localPosition.dy.clamp(imageRect.top, imageRect.bottom),
      );
    }

    final imageX =
        (localPosition.dx - displayOffset.dx) /
        displaySize.width *
        imageSize.width;
    final imageY =
        (localPosition.dy - displayOffset.dy) /
        displaySize.height *
        imageSize.height;

    _currentPanLocalPosition = localPosition;
    setState(() {
      _currentPathPoints.add(DrawingPoint(point: Offset(imageX, imageY)));
    });
  }

  void _undo() {
    if (_undoHistory.isNotEmpty)
      setState(() => _paths = _undoHistory.removeLast());
  }

  void _clearMask() {
    setState(() {
      _undoHistory.add(List.from(_paths));
      _paths.clear();
    });
  }

  Future<Uint8List?> _generateMask() async {
    // Keep this here as it relies heavily on UI state (_paths, _decodedImage)
    if (_decodedImage == null || _canvasRenderedSize == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final imageSize = Size(
      _decodedImage!.width.toDouble(),
      _decodedImage!.height.toDouble(),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
      Paint()..color = Colors.black,
    );

    // Calculate Aspect Ratios for scaling
    final imageAspectRatio = imageSize.width / imageSize.height;
    final containerAspectRatio =
        _canvasRenderedSize!.width / _canvasRenderedSize!.height;
    late final Size displaySize;

    if (imageAspectRatio > containerAspectRatio) {
      displaySize = Size(
        _canvasRenderedSize!.width,
        _canvasRenderedSize!.width / imageAspectRatio,
      );
    } else {
      displaySize = Size(
        _canvasRenderedSize!.height * imageAspectRatio,
        _canvasRenderedSize!.height,
      );
    }

    final double scaleFactorX = imageSize.width / displaySize.width;
    final double scaleFactorY = imageSize.height / displaySize.height;
    final double averageScaleFactor = (scaleFactorX + scaleFactorY) / 2;

    canvas.saveLayer(
      Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
      Paint(),
    );

    for (final pathData in _paths) {
      if (pathData.points.isEmpty) continue;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = pathData.strokeWidth * averageScaleFactor
        ..style = PaintingStyle.stroke;

      if (pathData.mode == DrawingMode.draw) {
        paint.color = Colors.white;
        paint.blendMode = BlendMode.srcOver;
      } else {
        paint.color = Colors.transparent;
        paint.blendMode = BlendMode.clear;
      }

      final path = Path();
      for (int i = 0; i < pathData.points.length; i++) {
        final point = pathData.points[i].point;
        if (i == 0)
          path.moveTo(point.dx, point.dy);
        else
          path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      imageSize.width.toInt(),
      imageSize.height.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final uint8List = byteData?.buffer.asUint8List();

    if (widget.onMaskGenerated != null && uint8List != null) {
      widget.onMaskGenerated!(uint8List);
    }
    return uint8List;
  }

  // --- Generation Logic ---

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
      globalPageIndex.value = 1;

      final imageBytes = await _imageFile!.readAsBytes();
      final maskBytes = await _generateMask();
      final loraStrings = GenerationLogic.buildLoraPromptAddition(
        _selectedLoras,
        _selectedLoraTags,
      );

      final newImages = await GenerationLogic.generateImg2Img(
        prompt: userPrompt.text,
        imageBytes: imageBytes,
        maskBytes: maskBytes,
        loraPromptAdditions: loraStrings,
      );

      final currentImages = Set<String>.from(globalResultImages.value);
      currentImages.addAll(newImages);
      globalResultImages.value = currentImages;

      ProgressService().stopProgressPolling();
    } catch (e) {
      ProgressService().stopProgressPolling();
      if (mounted) _showError('Error generating image: ${e.toString()}');
      print('Error in generateImage: $e');
    }
  }

  // --- Checkpoint Tester Logic ---

  Future<void> _startCheckpointTesting(List<String> checkpoints) async {
    if (_imageFile == null) {
      _showError('Please select an image first');
      return;
    }
    if (userPrompt.text.isEmpty) {
      _showError('Please enter a prompt first');
      return;
    }

    await checkServerStatus();
    if (!globalServerStatus.value) {
      _showError('Server not connected');
      return;
    }

    // Save Config
    _originalConfig = CheckpointData(
      title: globalCurrentCheckpointName,
      imageURL: '',
      samplingSteps: globalCurrentSamplingSteps,
      samplingMethod: globalCurrentSamplingMethod,
      cfgScale: globalCurrentCfgScale,
      resolutionHeight: globalCurrentResolutionHeight,
      resolutionWidth: globalCurrentResolutionWidth,
    );

    setState(() => _isCheckpointTesting = true);

    // Update Global UI
    globalIsCheckpointTesting.value = true;
    globalTotalCheckpointsToTest.value = checkpoints.length;
    globalPageIndex.value = 1;

    for (int i = 0; i < checkpoints.length; i++) {
      if (!_isCheckpointTesting) break;

      globalCurrentCheckpointTestIndex.value = i;
      globalCurrentTestingCheckpoint.value = checkpoints[i];

      await _testCheckpoint(checkpoints[i]);
      if (i < checkpoints.length - 1)
        await Future.delayed(const Duration(seconds: 1));
    }

    // Restore Config
    if (_originalConfig != null) {
      globalCurrentCheckpointName = _originalConfig!.title;
      globalCurrentSamplingSteps = _originalConfig!.samplingSteps;
      globalCurrentSamplingMethod = _originalConfig!.samplingMethod;
      globalCurrentCfgScale = _originalConfig!.cfgScale;
      globalCurrentResolutionWidth = _originalConfig!.resolutionWidth;
      globalCurrentResolutionHeight = _originalConfig!.resolutionHeight;
      await setCheckpoint();
      saveCheckpointDataMap();
    }

    setState(() => _isCheckpointTesting = false);
    globalIsCheckpointTesting.value = false;
    globalCurrentTestingCheckpoint.value = null;
  }

  Future<void> _testCheckpoint(String checkpointName) async {
    try {
      globalIsChangingCheckpoint.value = true;

      final data = globalCheckpointDataMap[checkpointName];
      if (data == null) {
        globalIsChangingCheckpoint.value = false;
        return;
      }

      globalCurrentCheckpointName = checkpointName;
      globalCurrentSamplingSteps = data.samplingSteps;
      globalCurrentSamplingMethod = data.samplingMethod;
      globalCurrentCfgScale = data.cfgScale;
      globalCurrentResolutionWidth = data.resolutionWidth;
      globalCurrentResolutionHeight = data.resolutionHeight;
      saveCheckpointDataMap();

      await setCheckpoint();
      await Future.delayed(const Duration(milliseconds: 500));
      globalIsChangingCheckpoint.value = false;
      await generateImage();
    } catch (e) {
      globalIsChangingCheckpoint.value = false;
      if (mounted) _showError('Error testing $checkpointName: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
              border: Border.all(
                color: Colors.cyan.shade700.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyan.shade900.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.cloud_upload_rounded,
              size: 56,
              color: Colors.cyan.shade300,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to Upload Image',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select an image to start drawing mask',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWithDrawing() {
    final imageSize = Size(
      _decodedImage!.width.toDouble(),
      _decodedImage!.height.toDouble(),
    );
    final containerSize = _canvasRenderedSize ?? Size.zero;
    final imageAspectRatio = imageSize.width / imageSize.height;
    final containerAspectRatio = containerSize.width / containerSize.height;

    // Calculate displayRect for Zoom Preview
    late final Rect displayRect;
    if (imageAspectRatio > containerAspectRatio) {
      final h = containerSize.width / imageAspectRatio;
      displayRect = Rect.fromLTWH(
        0,
        (containerSize.height - h) / 2,
        containerSize.width,
        h,
      );
    } else {
      final w = containerSize.height * imageAspectRatio;
      displayRect = Rect.fromLTWH(
        (containerSize.width - w) / 2,
        0,
        w,
        containerSize.height,
      );
    }

    final double calculatedZoomFactor =
        1.0 + (100.0 - _strokeWidth) / 100.0 * 3.0;

    return Column(
      children: [
        // --- DRAWING AREA ---
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasRenderedSize = constraints.biggest;
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: RawGestureDetector(
                  gestures: <Type, GestureRecognizerFactory>{
                    AlwaysWinPanGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          AlwaysWinPanGestureRecognizer
                        >(() => AlwaysWinPanGestureRecognizer(), (
                          AlwaysWinPanGestureRecognizer instance,
                        ) {
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
                      Positioned.fill(
                        child: Image.file(_imageFile!, fit: BoxFit.contain),
                      ),
                      if (_decodedImage != null)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: MaskPainter(
                              paths: [
                                ..._paths,
                                if (_currentPathPoints.isNotEmpty)
                                  DrawingPath(
                                    points: _currentPathPoints,
                                    mode: _currentMode,
                                    strokeWidth: _strokeWidth,
                                  ),
                              ],
                              imageSize: imageSize,
                              containerSize: constraints.biggest,
                            ),
                          ),
                        ),
                      if (_isDrawing &&
                          _currentPanLocalPosition != null &&
                          _canvasRenderedSize != null)
                        Positioned(
                          left: 16,
                          top: 16,
                          child: IgnorePointer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: ZoomPreviewWidget(
                                decodedImage: _decodedImage!,
                                allPaths: _paths,
                                currentPath: _currentPathPoints,
                                currentDrawingMode: _currentMode,
                                strokeWidth: _strokeWidth,
                                currentDrawingPoint: _currentPanLocalPosition!,
                                originalCanvasSize: _canvasRenderedSize!,
                                zoomFactor: calculatedZoomFactor,
                                displayRect: displayRect,
                              ),
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

        // --- TOOLBAR AREA ---
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(22),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // Top Row: Tools
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildModeButton(
                          DrawingMode.draw,
                          Icons.brush_rounded,
                          'Draw',
                        ),
                        const SizedBox(width: 4),
                        _buildModeButton(
                          DrawingMode.erase,
                          Icons.auto_fix_high_rounded,
                          'Erase',
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _buildActionIcon(
                        icon: Icons.undo_rounded,
                        onPressed: _undoHistory.isNotEmpty ? _undo : null,
                        tooltip: "Undo",
                      ),
                      const SizedBox(width: 4),
                      _buildActionIcon(
                        icon: Icons.layers_clear_rounded,
                        onPressed: _paths.isNotEmpty ? _clearMask : null,
                        tooltip: "Clear Mask",
                      ),
                      const SizedBox(width: 4),
                      _buildActionIcon(
                        icon: Icons.replay_rounded,
                        onPressed: _resetImage,
                        tooltip: "Reset Image",
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Bottom Row: Stroke Slider
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.circle,
                      size: 14,
                      color: Colors.cyan.shade300,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.cyan.shade400,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                        thumbColor: Colors.white,
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: _strokeWidth,
                        min: 1.0,
                        max: 100.0,
                        divisions: 99,
                        label: _strokeWidth.round().toString(),
                        onChanged: (value) =>
                            setState(() => _strokeWidth = value),
                      ),
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

  Widget _buildModeButton(DrawingMode mode, IconData icon, String label) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _currentMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyan.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required VoidCallback? onPressed,
    String? tooltip,
    bool isDestructive = false,
  }) {
    final isDisabled = onPressed == null;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDestructive && !isDisabled
                  ? Colors.red.shade900.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDisabled
                  ? Colors.white.withValues(alpha: 0.2)
                  : (isDestructive ? Colors.red.shade300 : Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).requestFocus(FocusNode());
      },
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            // 1. IMAGE CANVAS AREA
            GestureDetector(
              onTap: _imageFile == null ? _pickImage : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 600,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _imageFile != null
                      ? Colors.grey.shade900
                      : Colors.grey.shade800.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(
                    color: _imageFile != null
                        ? Colors.cyan.shade900
                        : Colors.white.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                  boxShadow: _imageFile != null
                      ? [
                          BoxShadow(
                            color: Colors.cyan.shade900.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: -5,
                          ),
                        ]
                      : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22.0),
                  child: _imageFile == null
                      ? _buildUploadPrompt()
                      : _buildImageWithDrawing(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 2. PROMPT & ACTIONS AREA
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade900.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Prompt Header ---
                  Row(
                    children: [
                      Icon(
                        Icons.edit_note,
                        color: Colors.cyan.shade300,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Positive Prompt",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // --- Prompt TextField ---
                  TextField(
                    focusNode: _promptFocusNode,
                    controller: userPrompt,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                    ),
                    maxLines: null,
                    minLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Describe what you want to generate...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.cyan.shade300.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // --- Action Buttons Row ---
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedGenButton(
                          onTap: () {
                            FocusScope.of(context).requestFocus(FocusNode());
                            if (userPrompt.text.isNotEmpty) {
                              setState(() {
                                globalInpaintHistory.add(userPrompt.text);
                                saveInpaintHistory();
                              });
                              generateImage();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedOptionButton(
                        icon: Icons.science,
                        tooltip: 'Checkpoint Tester',
                        onTap: () {
                          FocusScope.of(context).requestFocus(FocusNode());
                          showCheckpointTesterModal(context, (checkpoints) {
                            _startCheckpointTesting(checkpoints);
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      AnimatedOptionButton(
                        icon: Icons.auto_awesome_mosaic,
                        tooltip: 'Loras',
                        onTap: () {
                          FocusScope.of(context).requestFocus(FocusNode());
                          showLorasModal(
                            context,
                            _selectedLoras,
                            _selectedLoraTags,
                            (newLoras, newTags) {
                              setState(() {
                                _selectedLoras = newLoras;
                                _selectedLoraTags = newTags;
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      AnimatedOptionButton(
                        icon: Icons.history,
                        tooltip: 'History',
                        onTap: () {
                          FocusScope.of(context).requestFocus(FocusNode());
                          showInpaintHistory(context, (selectedItem) {
                            setState(() {
                              userPrompt.text = selectedItem;
                            });
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
