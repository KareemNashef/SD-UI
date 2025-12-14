// image_upload_container.dart:
// ==================== Image Container ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:path_provider/path_provider.dart'; // FIX 2: Required for temp directory

// Local imports - Logic
import 'package:sd_companion/logic/drawing_models.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/progress_service.dart';
import 'package:sd_companion/logic/api_calls.dart';

// Local imports - Elements
import 'package:sd_companion/elements/mask_painter.dart';
import 'package:sd_companion/elements/zoom_preview_widget.dart';
import 'package:sd_companion/elements/animated_tiles.dart';

class AlwaysWinPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'alwaysWin';
}

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
  List<String> _checkpointsToTest = [];
  int _currentCheckpointIndex = 0;
  String? _currentTestingCheckpoint;
  CheckpointData? _originalConfig;

  // Lora Variables
  Map<String, double> _selectedLoras = {};
  Map<String, Set<String>> _selectedLoraTags = {};
  Map<String, bool> _expandedLoras = {};
  Map<String, bool> _showAllTags = {};

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    // FIX 2: Listen for requests to edit an image from the results carousel.
    globalImageToEdit.addListener(_onEditImageRequest);
  }

  @override
  void dispose() {
    userPrompt.dispose();
    _promptFocusNode.dispose();
    // FIX 2: Remove the listener to prevent memory leaks.
    globalImageToEdit.removeListener(_onEditImageRequest);
    super.dispose();
  }

  // ===== Class Functions ===== //

  /// FIX 2: Handles the request to load an image for editing.
  Future<void> _onEditImageRequest() async {
    final imageUrl = globalImageToEdit.value;
    if (imageUrl == null || !mounted) return;

    // Reset the notifier so this doesn't trigger again on rebuild.
    globalImageToEdit.value = null;

    await _loadImageFromUrl(imageUrl);
  }

  /// FIX 2: Loads an image from a URL (network or base64) and resets the canvas.
  Future<void> _loadImageFromUrl(String url) async {
    try {
      Uint8List imageBytes;

      if (url.startsWith('data:image/')) {
        // Handle base64 data URL
        final commaIndex = url.indexOf(',');
        if (commaIndex != -1) {
          final base64Data = url.substring(commaIndex + 1);
          imageBytes = base64Decode(base64Data);
        } else {
          throw Exception('Invalid base64 data URL');
        }
      } else {
        // Handle standard network URL
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        } else {
          throw Exception('Failed to download image: ${response.statusCode}');
        }
      }

      // To use Image.file and have a consistent workflow, we write the bytes
      // to a temporary file.
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(tempPath);
      await file.writeAsBytes(imageBytes);

      final ui.Image image = await decodeImageFromList(imageBytes);

      // This is the "reset the container" step.
      setState(() {
        _imageFile = file;
        _decodedImage = image;
        _paths.clear();
        _undoHistory.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Error loading image for editing: $e'),
              backgroundColor: Colors.red,
            ),
          );
      }
    }
  }

  void _showInpaintHistory(BuildContext context) {
    // A local, mutable copy of the history for the modal
    final historyList = globalInpaintHistory.toList().reversed.toList();

    // State for multi-selection
    bool isMultiSelectMode = false;
    Set<String> selectedItems = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            void deleteSelected() {
              globalInpaintHistory.removeAll(selectedItems);
              saveInpaintHistory(); // Assuming this function exists in your global scope
              modalSetState(() {
                historyList.removeWhere((item) => selectedItems.contains(item));
                selectedItems.clear();
                isMultiSelectMode = false;
              });
            }

            void clearAll() {
              globalInpaintHistory.clear();
              saveInpaintHistory();
              modalSetState(() {
                historyList.clear();
              });
              Navigator.pop(context);
            }

            return FractionallySizedBox(
              heightFactor: 0.6, // Increased slightly for better visibility
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24.0),
                    topRight: Radius.circular(24.0),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // --- HEADER ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history,
                                color: Colors.cyan.shade300,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isMultiSelectMode
                                    ? 'Select Items'
                                    : 'Prompt History',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          // Close or Cancel Selection
                          IconButton(
                            icon: Icon(
                              isMultiSelectMode
                                  ? Icons.close
                                  : Icons.keyboard_arrow_down,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              if (isMultiSelectMode) {
                                modalSetState(() {
                                  isMultiSelectMode = false;
                                  selectedItems.clear();
                                });
                              } else {
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // --- Clear All Button (Only in Normal Mode) ---
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      child: (!isMultiSelectMode && historyList.isNotEmpty)
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        backgroundColor: Colors.grey.shade900,
                                        title: const Text(
                                          'Clear History?',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        content: const Text(
                                          'Are you sure you want to delete all prompts?',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            child: const Text('Cancel'),
                                            onPressed: () =>
                                                Navigator.pop(dialogContext),
                                          ),
                                          TextButton(
                                            child: Text(
                                              'Clear All',
                                              style: TextStyle(
                                                color: Colors.red.shade400,
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.pop(dialogContext);
                                              clearAll();
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  icon: Icon(
                                    Icons.delete_forever,
                                    color: Colors.red.shade400,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Clear All',
                                    style: TextStyle(
                                      color: Colors.red.shade400,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // --- CONTENT ---
                    if (historyList.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.history_toggle_off,
                                size: 48,
                                color: Colors.white24,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No history yet',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: historyList.length,
                          itemBuilder: (context, index) {
                            final item = historyList[index];
                            final isSelected = selectedItems.contains(item);

                            // We wrap in Dismissible only if NOT in multi-select mode
                            // (Swipe to delete usually conflicts with multi-select UX)
                            Widget content = AnimatedHistoryTile(
                              key: ValueKey(item),
                              text: item,
                              isMultiSelectMode: isMultiSelectMode,
                              isSelected: isSelected,
                              onTap: () {
                                modalSetState(() {
                                  if (isMultiSelectMode) {
                                    if (isSelected) {
                                      selectedItems.remove(item);
                                      if (selectedItems.isEmpty)
                                        isMultiSelectMode = false;
                                    } else {
                                      selectedItems.add(item);
                                    }
                                  } else {
                                    // Assuming 'userPrompt' is your global TextEditingController
                                    userPrompt.text = item;
                                    Navigator.pop(context);
                                  }
                                });
                              },
                              onLongPress: () {
                                modalSetState(() {
                                  isMultiSelectMode = true;
                                  selectedItems.add(item);
                                });
                              },
                            );

                            if (isMultiSelectMode) return content;

                            return Dismissible(
                              key: Key(item),
                              direction: DismissDirection.endToStart,
                              onDismissed: (direction) {
                                setState(() {
                                  globalInpaintHistory.remove(item);
                                  saveInpaintHistory();
                                });
                                modalSetState(() {
                                  historyList.removeAt(index);
                                });
                              },
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900.withValues(
                                    alpha: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20.0),
                                child: const Icon(
                                  Icons.delete_sweep_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              child: content,
                            );
                          },
                        ),
                      ),

                    // --- BOTTOM ACTION BUTTON ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SafeArea(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: isMultiSelectMode
                                ? LinearGradient(
                                    colors: [
                                      Colors.red.shade500,
                                      Colors.orange.shade500,
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      Colors.grey.shade800,
                                      Colors.grey.shade700,
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isMultiSelectMode
                                ? [
                                    BoxShadow(
                                      color: Colors.red.shade500.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: isMultiSelectMode
                                  ? deleteSelected
                                  : () => Navigator.pop(context),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isMultiSelectMode
                                        ? Icons.delete_outline
                                        : Icons.close,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isMultiSelectMode
                                        ? 'Delete ${selectedItems.length} Selected'
                                        : 'Close',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
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
      },
    );
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

    // ISSUE 4 FIX: Don't clamp to stroke-adjusted rect, allow drawing at edges
    // Just clamp to the image bounds without stroke adjustment
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

  Future<Uint8List?> _generateMask() async {
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
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
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

  Future<void> generateImage() async {
    if (_imageFile == null || _decodedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await checkServerStatus();
    if (!globalServerStatus.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server not connected'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      ProgressService().startProgressPolling();
      globalPageIndex.value = 1;

      final url = Uri.parse(
        'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/img2img',
      );

      final headers = {'Content-Type': 'application/json'};
      final imageBytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final maskBytes = await _generateMask();
      final base64Mask = maskBytes != null ? base64Encode(maskBytes) : null;

      final body = jsonEncode({
        "prompt": userPrompt.text + _buildLoraPromptAddition(),
        "negative_prompt": globalNegativePrompt,
        "sampler_name": globalCurrentSamplingMethod,
        "scheduler": "Automatic",
        "width": globalCurrentResolutionWidth.toInt(),
        "height": globalCurrentResolutionHeight.toInt(),
        "n_iter": globalBatchSize,
        "steps": globalCurrentSamplingSteps.toInt(),
        "cfg_scale": globalCurrentCfgScale,
        "denoising_strength": globalDenoiseStrength,
        "init_images": [base64Image],
        "mask": base64Mask,
        "save_images": true,
        "send_images": true,
        "mask_blur": globalMaskBlur,
        "inpainting_fill": _getInpaintingFillValue(globalMaskFill),
        "inpaint_full_res_padding": 32,
        "inpaint_full_res": true,
        "inpainting_mask_invert": 0,
        "mask_round": true,
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final images = responseData['images'] as List<dynamic>?;

        if (images != null && images.isNotEmpty) {
          final Set<String> newImages = {};
          final int start = images.length > 1 ? 1 : 0;
          for (int i = start; i < images.length; i++) {
            final base64ImageData = images[i] as String;
            final dataUrl = 'data:image/png;base64,$base64ImageData';
            newImages.add(dataUrl);
          }

          final currentImages = Set<String>.from(globalResultImages.value);
          currentImages.addAll(newImages);
          globalResultImages.value = currentImages;

          ProgressService().stopProgressPolling();
        } else {
          throw Exception('No images generated');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      ProgressService().stopProgressPolling();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating image: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      print('Error in generateImage: $e');
    }
  }

  int _getInpaintingFillValue(String maskFill) {
    switch (maskFill.toLowerCase()) {
      case 'fill':
        return 0;
      case 'original':
        return 1;
      case 'latent noise':
        return 2;
      case 'latent nothing':
        return 3;
      default:
        return 0;
    }
  }

  void _showCheckpointTesterModal(BuildContext context) {
    final availableCheckpoints = globalCheckpointDataMap.keys.toList();

    if (availableCheckpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No checkpoints available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Set<String> selectedCheckpoints = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            return FractionallySizedBox(
              heightFactor: 0.75,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24.0),
                    topRight: Radius.circular(24.0),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // --- HEADER ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.science,
                                color: Colors.cyan.shade300,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Checkpoint Tester',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // --- Select All Row ---
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${selectedCheckpoints.length} selected',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              modalSetState(() {
                                if (selectedCheckpoints.length ==
                                    availableCheckpoints.length) {
                                  selectedCheckpoints.clear();
                                } else {
                                  selectedCheckpoints = Set.from(
                                    availableCheckpoints,
                                  );
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                selectedCheckpoints.length ==
                                        availableCheckpoints.length
                                    ? 'Deselect All'
                                    : 'Select All',
                                style: TextStyle(
                                  color: Colors.cyan.shade300,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- LIST ---
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: availableCheckpoints.length,
                        itemBuilder: (context, index) {
                          final checkpointName = availableCheckpoints[index];
                          final data = globalCheckpointDataMap[checkpointName];

                          return AnimatedCheckpointTile(
                            key: ValueKey(checkpointName),
                            name: checkpointName,
                            data: data,
                            isSelected: selectedCheckpoints.contains(
                              checkpointName,
                            ),
                            onTap: () {
                              modalSetState(() {
                                if (selectedCheckpoints.contains(
                                  checkpointName,
                                )) {
                                  selectedCheckpoints.remove(checkpointName);
                                } else {
                                  selectedCheckpoints.add(checkpointName);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),

                    // --- BOTTOM ACTION BUTTON ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SafeArea(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: selectedCheckpoints.isEmpty
                                ? LinearGradient(
                                    colors: [
                                      Colors.grey.shade800,
                                      Colors.grey.shade700,
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      Colors.cyan.shade500,
                                      Colors.lime.shade500,
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: selectedCheckpoints.isEmpty
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.cyan.shade500.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: selectedCheckpoints.isEmpty
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      _startCheckpointTesting(
                                        selectedCheckpoints.toList(),
                                      );
                                    },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    color: selectedCheckpoints.isEmpty
                                        ? Colors.white38
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Start Testing (${selectedCheckpoints.length})',
                                    style: TextStyle(
                                      color: selectedCheckpoints.isEmpty
                                          ? Colors.white38
                                          : Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
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
      },
    );
  }

  Future<void> _startCheckpointTesting(List<String> checkpoints) async {
    if (_imageFile == null || _decodedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (userPrompt.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a prompt first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await checkServerStatus();
    if (!globalServerStatus.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server not connected'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Save original configuration
    _originalConfig = CheckpointData(
      title: globalCurrentCheckpointName,
      imageURL: '',
      samplingSteps: globalCurrentSamplingSteps,
      samplingMethod: globalCurrentSamplingMethod,
      cfgScale: globalCurrentCfgScale,
      resolutionHeight: globalCurrentResolutionHeight,
      resolutionWidth: globalCurrentResolutionWidth,
    );

    setState(() {
      _isCheckpointTesting = true;
      _checkpointsToTest = checkpoints;
      _currentCheckpointIndex = 0;
    });

    // ADD THESE LINES: Update global notifiers for ProgressOverlay
    globalIsCheckpointTesting.value = true;
    globalTotalCheckpointsToTest.value = checkpoints.length;

    // Switch to results page
    globalPageIndex.value = 1;

    for (int i = 0; i < checkpoints.length; i++) {
      if (!_isCheckpointTesting) break; // Allow cancellation

      setState(() {
        _currentCheckpointIndex = i;
        _currentTestingCheckpoint = checkpoints[i];
      });

      // ADD THESE LINES: Update global notifiers in the loop
      globalCurrentCheckpointTestIndex.value = i;
      globalCurrentTestingCheckpoint.value = checkpoints[i];

      await _testCheckpoint(checkpoints[i]);

      // Small delay between tests
      if (i < checkpoints.length - 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Restore original configuration
    if (_originalConfig != null) {
      setState(() {
        globalCurrentCheckpointName = _originalConfig!.title;
        globalCurrentSamplingSteps = _originalConfig!.samplingSteps;
        globalCurrentSamplingMethod = _originalConfig!.samplingMethod;
        globalCurrentCfgScale = _originalConfig!.cfgScale;
        globalCurrentResolutionWidth = _originalConfig!.resolutionWidth;
        globalCurrentResolutionHeight = _originalConfig!.resolutionHeight;
      });
      await setCheckpoint();
      saveCheckpointDataMap();
    }

    setState(() {
      _isCheckpointTesting = false;
      _currentTestingCheckpoint = null;
    });

    // ADD THESE LINES: Reset global notifiers at the end
    globalIsCheckpointTesting.value = false;
    globalCurrentTestingCheckpoint.value = null;
  }

  Future<void> _testCheckpoint(String checkpointName) async {
    try {
      // Set changing checkpoint flag BEFORE changing checkpoint
      globalIsChangingCheckpoint.value = true;

      // Apply checkpoint configuration
      final data = globalCheckpointDataMap[checkpointName];
      if (data == null) {
        globalIsChangingCheckpoint.value = false;
        return;
      }

      setState(() {
        globalCurrentCheckpointName = checkpointName;
        globalCurrentSamplingSteps = data.samplingSteps;
        globalCurrentSamplingMethod = data.samplingMethod;
        globalCurrentCfgScale = data.cfgScale;
        globalCurrentResolutionWidth = data.resolutionWidth;
        globalCurrentResolutionHeight = data.resolutionHeight;
      });
      saveCheckpointDataMap();

      // Change checkpoint on server
      await setCheckpoint();

      // Small delay to ensure checkpoint is loaded
      await Future.delayed(const Duration(milliseconds: 500));

      // Clear the changing checkpoint flag BEFORE generating
      globalIsChangingCheckpoint.value = false;

      // Generate image
      await generateImage();
    } catch (e) {
      globalIsChangingCheckpoint.value = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error testing checkpoint $checkpointName: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error in _testCheckpoint: $e');
    }
  }

  String _buildLoraPromptAddition() {
    if (_selectedLoras.isEmpty) return '';

    List<String> loraStrings = [];

    _selectedLoras.forEach((loraName, strength) {
      if (strength > 0) {
        final loraData = globalLoraDataMap[loraName];
        if (loraData != null) {
          // Add the lora with its strength
          loraStrings.add(
            '<lora:${loraData.alias}:${strength.toStringAsFixed(2)}>',
          );

          // Add selected tags if any
          final selectedTags = _selectedLoraTags[loraName];
          if (selectedTags != null && selectedTags.isNotEmpty) {
            loraStrings.addAll(selectedTags);
          }
        }
      }
    });

    return loraStrings.isEmpty ? '' : ' ${loraStrings.join(' ')}';
  }

void _showLorasModal(BuildContext context) {
    // We removed the initial check for empty Loras here
    // so that the user can open the modal to Refresh if the list is empty.

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        // Variables for the refresh animation state
        bool isRefreshing = false;
        double refreshTurns = 0.0;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            // Re-fetch the list every time state changes (e.g. after refresh)
            final availableLoras = globalLoraDataMap.keys.toList()..sort();

            return FractionallySizedBox(
              heightFactor: 0.75,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24.0),
                    topRight: Radius.circular(24.0),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // --- Header ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_mosaic,
                                color: Colors.cyan.shade300,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Loras',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // --- Refresh Button ---
                              IconButton(
                                icon: AnimatedRotation(
                                  turns: refreshTurns,
                                  duration: const Duration(seconds: 1),
                                  curve: Curves.easeInOut,
                                  child: Icon(
                                    Icons.refresh_rounded,
                                    color: isRefreshing
                                        ? Colors.cyan.shade300
                                        : Colors.white38,
                                  ),
                                ),
                                onPressed: () async {
                                  if (isRefreshing) return;

                                  // Start Animation
                                  modalSetState(() {
                                    isRefreshing = true;
                                    refreshTurns += 1.0;
                                  });

                                  // Call the refresh function
                                  await loadLoraDataFromServer();

                                  // Stop Animation & Rebuild UI with new data
                                  if (context.mounted) {
                                    modalSetState(() {
                                      isRefreshing = false;
                                    });
                                    // Also update parent state to reflect changes if needed
                                    setState(() {});
                                  }
                                },
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (_selectedLoras.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.cyan.shade900.withValues(
                                      alpha: 0.5,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.cyan.shade700,
                                    ),
                                  ),
                                  child: Text(
                                    '${_selectedLoras.length} active',
                                    style: TextStyle(
                                      color: Colors.cyan.shade200,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // --- Clear Button ---
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _selectedLoras.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    modalSetState(() {
                                      setState(() {
                                        _selectedLoras.clear();
                                        _selectedLoraTags.clear();
                                        _expandedLoras.clear();
                                        _showAllTags.clear();
                                      });
                                    });
                                  },
                                  icon: Icon(
                                    Icons.clear_all,
                                    color: Colors.red.shade400,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Clear All',
                                    style: TextStyle(
                                      color: Colors.red.shade400,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // --- List ---
                    Expanded(
                      child: availableLoras.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 48,
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No Loras Found',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  if (!isRefreshing)
                                    TextButton(
                                      onPressed: () async {
                                        modalSetState(() {
                                          isRefreshing = true;
                                          refreshTurns += 1.0;
                                        });
                                        await loadLoraDataFromServer();
                                        if (context.mounted) {
                                          modalSetState(() {
                                            isRefreshing = false;
                                          });
                                          setState(() {});
                                        }
                                      },
                                      child: const Text(
                                        "Tap to refresh",
                                        style: TextStyle(color: Colors.cyan),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 8.0,
                              ),
                              itemCount: availableLoras.length,
                              itemBuilder: (context, index) {
                                final loraName = availableLoras[index];
                                final loraData = globalLoraDataMap[loraName]!;

                                return AnimatedLoraTile(
                                  key: ValueKey(loraName),
                                  loraName: loraName,
                                  loraData: loraData,
                                  isSelected:
                                      _selectedLoras.containsKey(loraName),
                                  strength: _selectedLoras[loraName] ?? 0.0,
                                  isExpanded:
                                      _expandedLoras[loraName] ?? false,
                                  selectedTags:
                                      _selectedLoraTags[loraName] ?? {},
                                  showAllTags: _showAllTags[loraName] ?? false,
                                  onToggleSelection: () {
                                    modalSetState(() {
                                      setState(() {
                                        if (_selectedLoras
                                            .containsKey(loraName)) {
                                          _selectedLoras.remove(loraName);
                                        } else {
                                          _selectedLoras[loraName] = 1.0;
                                        }
                                      });
                                    });
                                  },
                                  onStrengthChanged: (val) {
                                    modalSetState(() {
                                      setState(() {
                                        if (val == 0) {
                                          _selectedLoras.remove(loraName);
                                          _selectedLoraTags.remove(loraName);
                                        } else {
                                          _selectedLoras[loraName] = val;
                                        }
                                      });
                                    });
                                  },
                                  onToggleExpand: () {
                                    modalSetState(() {
                                      setState(() {
                                        _expandedLoras[loraName] =
                                            !(_expandedLoras[loraName] ??
                                                false);
                                      });
                                    });
                                  },
                                  onToggleTag: (tag) {
                                    modalSetState(() {
                                      setState(() {
                                        if (!_selectedLoras
                                            .containsKey(loraName)) {
                                          _selectedLoras[loraName] = 0.5;
                                        }
                                        if (!_selectedLoraTags
                                            .containsKey(loraName)) {
                                          _selectedLoraTags[loraName] = {};
                                        }

                                        final tags =
                                            _selectedLoraTags[loraName]!;
                                        if (tags.contains(tag)) {
                                          tags.remove(tag);
                                        } else {
                                          tags.add(tag);
                                        }
                                      });
                                    });
                                  },
                                  onToggleShowAllTags: () {
                                    modalSetState(() {
                                      setState(() {
                                        _showAllTags[loraName] =
                                            !(_showAllTags[loraName] ?? false);
                                      });
                                    });
                                  },
                                );
                              },
                            ),
                    ),

                    // --- Bottom Apply Button ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SafeArea(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _selectedLoras.isEmpty
                                  ? [Colors.grey.shade700, Colors.grey.shade600]
                                  : [
                                      Colors.cyan.shade500,
                                      Colors.lime.shade500,
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _selectedLoras.isEmpty
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.cyan.shade500.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.pop(context),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _selectedLoras.isEmpty
                                        ? Icons.close
                                        : Icons.check_rounded,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _selectedLoras.isEmpty
                                        ? 'Close'
                                        : 'Apply ${_selectedLoras.length} Lora${_selectedLoras.length > 1 ? 's' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
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
      },
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
                // Rounded corners only at the top (bottom connects to toolbar)
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
                                currentDrawingPoint:
                                    _currentPanLocalPosition!,
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
                  // Mode Switcher (Pill shape)
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

                  // Actions (Undo/Clear/Reset)
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
                        overlayColor: Colors.cyan.shade400.withValues(
                          alpha: 0.2,
                        ),
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
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
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 30,
                    child: Text(
                      _strokeWidth.toInt().toString(),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: Colors.cyan.shade200,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
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
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyan.shade900.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: -2,
                  ),
                ]
              : [],
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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

  InputDecoration modernInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withAlpha(128)),

      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.1),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),

      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  void deactivate() {
    _promptFocusNode.unfocus();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Hard Unfocus logic maintained
      onTap: () {
        FocusScope.of(context).requestFocus(FocusNode());
      },
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            // ===========================
            // 1. IMAGE CANVAS AREA
            // ===========================
            GestureDetector(
              onTap: _imageFile == null ? _pickImage : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 600, // Or use MediaQuery for responsiveness
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
                      ? _buildUploadPrompt() // Assuming this exists
                      : _buildImageWithDrawing(), // Assuming this exists
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ===========================
            // 2. PROMPT & ACTIONS AREA
            // ===========================
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
                      // 1. GENERATE BUTTON (Expanded)
                      Expanded(
                        child: _AnimatedGenButton(
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

                      // 2. UTILITY BUTTONS
                      _AnimatedOptionButton(
                        icon: Icons.science,
                        tooltip: 'Checkpoint Tester',
                        onTap: () {
                          FocusScope.of(context).requestFocus(FocusNode());
                          _showCheckpointTesterModal(context);
                        },
                      ),

                      const SizedBox(width: 8),

                      _AnimatedOptionButton(
                        icon: Icons.auto_awesome_mosaic,
                        tooltip: 'Loras',
                        onTap: () {
                          FocusScope.of(context).requestFocus(FocusNode());
                          _showLorasModal(context);
                        },
                      ),

                      const SizedBox(width: 8),

                      _AnimatedOptionButton(
                        icon: Icons.history,
                        tooltip: 'History',
                        onTap: () {
                          FocusScope.of(context).requestFocus(FocusNode());
                          _showInpaintHistory(context);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Extra padding at bottom for scrolling
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// HELPER ANIMATED WIDGETS
// (Add these to the bottom of the file)
// ==========================================

class _AnimatedGenButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AnimatedGenButton({required this.onTap});

  @override
  State<_AnimatedGenButton> createState() => _AnimatedGenButtonState();
}

class _AnimatedGenButtonState extends State<_AnimatedGenButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.lime.shade600, Colors.cyan.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.cyan.shade500.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text(
                'Generate',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedOptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _AnimatedOptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_AnimatedOptionButton> createState() => _AnimatedOptionButtonState();
}

class _AnimatedOptionButtonState extends State<_AnimatedOptionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Tooltip(
          message: widget.tooltip,
          child: Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
