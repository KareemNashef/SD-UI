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
import 'package:sd_companion/logic/api_calls.dart';

// Local imports - Logic
import 'package:sd_companion/logic/drawing_models.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/progress_service.dart';

// Local imports - Elements
import 'package:sd_companion/elements/mask_painter.dart';
import 'package:sd_companion/elements/zoom_preview_widget.dart';

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
      isScrollControlled: true, // Important for FractionallySizedBox
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            // Helper function to handle deleting selected items
            void deleteSelected() {
              // Remove from global state
              globalInpaintHistory.removeAll(selectedItems);
              saveInpaintHistory();

              // Update local state for the UI
              modalSetState(() {
                historyList.removeWhere((item) => selectedItems.contains(item));
                selectedItems.clear();
                isMultiSelectMode = false;
              });
            }

            return FractionallySizedBox(
              heightFactor: 0.4, // FIX 1: Keep modal size consistent
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade800.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16.0),
                    topRight: Radius.circular(16.0),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    // --- HEADER ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Show Cancel button in multi-select mode
                          if (isMultiSelectMode)
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                modalSetState(() {
                                  isMultiSelectMode = false;
                                  selectedItems.clear();
                                });
                              },
                            ),

                          // Title or Selection Count
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0),
                            child: Text(
                              isMultiSelectMode
                                  ? '${selectedItems.length} selected'
                                  : 'Prompt History',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),

                          // Show Delete button in multi-select mode
                          if (isMultiSelectMode)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                              ),
                              onPressed: selectedItems.isEmpty
                                  ? null
                                  : deleteSelected,
                            )
                          // Show Clear All button in normal mode
                          else if (historyList.isNotEmpty)
                            IconButton(
                              icon: const Icon(
                                Icons
                                    .delete_forever_outlined, // FIX 2: Clear All button
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Clear History?'),
                                    content: const Text(
                                      'Are you sure you want to delete all prompts from your history?',
                                    ),
                                    actions: [
                                      TextButton(
                                        child: const Text('Cancel'),
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                      ),
                                      TextButton(
                                        child: const Text('Clear All'),
                                        onPressed: () {
                                          globalInpaintHistory.clear();
                                          saveInpaintHistory();
                                          modalSetState(() {
                                            historyList.clear();
                                          });
                                          Navigator.pop(dialogContext);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                    // --- CONTENT ---
                    if (historyList.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            'Your prompt history is empty.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: historyList.length,
                          itemBuilder: (context, index) {
                            final item = historyList[index];
                            final isSelected = selectedItems.contains(item);

                            return Dismissible(
                              key: Key(item),
                              direction: isMultiSelectMode
                                  ? DismissDirection
                                        .none // Disable swipe in multi-select
                                  : DismissDirection.endToStart,
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
                                color: Colors.red.shade800,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0,
                                ),
                                child: const Icon(
                                  Icons.delete_sweep_outlined,
                                  color: Colors.white70,
                                ),
                              ),
                              child: ListTile(
                                // FIX 3: Multi-select logic
                                onLongPress: () {
                                  modalSetState(() {
                                    isMultiSelectMode = true;
                                    selectedItems.add(item);
                                  });
                                },
                                onTap: () {
                                  if (isMultiSelectMode) {
                                    modalSetState(() {
                                      if (isSelected) {
                                        selectedItems.remove(item);
                                      } else {
                                        selectedItems.add(item);
                                      }
                                    });
                                  } else {
                                    userPrompt.text = item;
                                    Navigator.pop(context);
                                  }
                                },
                                title: Text(
                                  item,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                // Visual feedback for selection
                                tileColor: isSelected
                                    ? Colors.purple.withValues(alpha: 0.2)
                                    : null,
                                trailing: isMultiSelectMode
                                    ? Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: isSelected
                                            ? Colors.purple.shade300
                                            : Colors.white54,
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
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
        "prompt": userPrompt.text,
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
          content: Text('No checkpoints available to test'),
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
              heightFactor: 0.6,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade800.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16.0),
                    topRight: Radius.circular(16.0),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.science_outlined,
                                color: Colors.cyan.shade400,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Checkpoint Tester',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
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

                    // Selection controls
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${selectedCheckpoints.length} of ${availableCheckpoints.length} selected',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
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
                            child: Text(
                              selectedCheckpoints.length ==
                                      availableCheckpoints.length
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: TextStyle(
                                color: Colors.cyan.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Checkpoint list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: availableCheckpoints.length,
                        itemBuilder: (context, index) {
                          final checkpointName = availableCheckpoints[index];
                          final isSelected = selectedCheckpoints.contains(
                            checkpointName,
                          );
                          final data = globalCheckpointDataMap[checkpointName];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.cyan.shade400.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.cyan.shade400.withValues(
                                        alpha: 0.5,
                                      )
                                    : Colors.white.withValues(alpha: 0.1),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              onTap: () {
                                modalSetState(() {
                                  if (isSelected) {
                                    selectedCheckpoints.remove(checkpointName);
                                  } else {
                                    selectedCheckpoints.add(checkpointName);
                                  }
                                });
                              },
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.cyan.shade400
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                checkpointName,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: data != null
                                  ? Text(
                                      '${data.resolutionWidth.toInt()}x${data.resolutionHeight.toInt()} • Steps: ${data.samplingSteps.toInt()} • CFG: ${data.cfgScale}',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontSize: 12,
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),

                    // Start button
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: selectedCheckpoints.isEmpty
                                  ? LinearGradient(
                                      colors: [
                                        Colors.grey.shade700,
                                        Colors.grey.shade600,
                                      ],
                                    )
                                  : LinearGradient(
                                      colors: [
                                        Colors.cyan.shade500,
                                        Colors.lime.shade500,
                                      ],
                                    ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: selectedCheckpoints.isEmpty
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _startCheckpointTesting(
                                          selectedCheckpoints.toList(),
                                        );
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16.0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Start Testing (${selectedCheckpoints.length})',
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

  // ===== Class Widgets ===== //

  Widget _buildUploadPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: Icon(
              Icons.cloud_upload_rounded,
              size: 64,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to Upload Image',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select an image to start drawing',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasRenderedSize = constraints.biggest;
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
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
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade800.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildModeButton(DrawingMode.draw, Icons.brush, 'Draw'),
                        _buildModeButton(
                          DrawingMode.erase,
                          Icons.auto_fix_high,
                          'Erase',
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.undo, color: Colors.white),
                        onPressed: _undoHistory.isNotEmpty ? _undo : null,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.layers_clear,
                          color: Colors.white,
                        ),
                        onPressed: _paths.isNotEmpty ? _clearMask : null,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.replay_circle_filled,
                          color: Colors.white,
                        ),
                        onPressed: _resetImage,
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(
                    Icons.line_weight,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  Expanded(
                    child: Slider(
                      value: _strokeWidth,
                      min: 1.0,
                      max: 100.0,
                      divisions: 99,
                      activeColor: Colors.cyan.shade400,
                      label: _strokeWidth.round().toString(),
                      onChanged: (value) =>
                          setState(() => _strokeWidth = value),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyan.shade400 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
      // 2. UPDATED: The "Hard" Unfocus
      // Instead of just .unfocus(), we explicitly request a new focus.
      // This stops the "momentary" unfocus issue.
      onTap: () {
        FocusScope.of(context).requestFocus(FocusNode());
      },
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        // 3. ADD THIS: Allows you to drag the screen down to dismiss keyboard
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            GestureDetector(
              onTap: _imageFile == null ? _pickImage : null,
              child: Container(
                height: 600,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: _imageFile == null
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.grey.shade800.withValues(alpha: 0.6),
                            Colors.grey.shade900.withValues(alpha: 0.8),
                          ],
                        )
                      : null,
                  color: _imageFile != null ? Colors.grey.shade900 : null,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: _imageFile == null
                    ? _buildUploadPrompt()
                    : _buildImageWithDrawing(),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade800.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    focusNode: _promptFocusNode,
                    controller: userPrompt,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    maxLines: null,
                    minLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter a prompt...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.lime.shade600,
                                  Colors.cyan.shade500,
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  // Unfocus immediately on Generate
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(FocusNode());
                                  if (userPrompt.text.isNotEmpty) {
                                    setState(() {
                                      globalInpaintHistory.add(userPrompt.text);
                                      saveInpaintHistory();
                                    });
                                    generateImage();
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Generate',
                                        style: TextStyle(
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
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: () {
                            // Hard Unfocus before modal
                            FocusScope.of(context).requestFocus(FocusNode());
                            _showCheckpointTesterModal(context);
                          },
                          icon: const Icon(
                            Icons.science_outlined,
                            color: Colors.white,
                          ),
                          tooltip: 'Checkpoint Tester',
                          splashRadius: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: () {
                            // Hard Unfocus before modal
                            FocusScope.of(context).requestFocus(FocusNode());
                            _showInpaintHistory(context);
                          },
                          icon: const Icon(Icons.history, color: Colors.white),
                          tooltip: 'Prompt History',
                          splashRadius: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
