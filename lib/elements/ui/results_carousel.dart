// ==================== Results Carousel ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modals/crop_modal.dart';
import 'package:sd_companion/elements/modals/metadata_modal.dart';
import 'package:sd_companion/elements/modals/resize_modal.dart';
import 'package:sd_companion/elements/modals/upscale_modal.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/models/generation_models.dart';
import 'package:sd_companion/logic/utils/image_metadata_parser.dart';

// Results Carousel Implementation

class ResultsCarousel extends StatefulWidget {
  const ResultsCarousel({super.key});

  @override
  State<ResultsCarousel> createState() => _ResultsCarouselState();
}

class _ResultsCarouselState extends State<ResultsCarousel> {
  // ===== Class Variables ===== //

  String? _selectedImageId;
  bool _isSaving = false;
  bool _isFetchingInfo = false;

  bool _isComparing = false;

  final Map<String, Uint8List> _imageCache = {}; // keyed by imageUrl
  List<String> _lastKnownImageIds = [];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    globalResultImages.addListener(_onImagesChanged);
    globalInputImage.addListener(_onInputChanged);
    _onImagesChanged(isInitialSetup: true);
  }

  @override
  void dispose() {
    globalResultImages.removeListener(_onImagesChanged);
    globalInputImage.removeListener(_onInputChanged);
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  // ===== Class Methods ===== //

  GeneratedImage? _findById(String? id) {
    if (id == null) return null;
    for (final image in globalResultImages.value) {
      if (image.id == id) return image;
    }
    return null;
  }

  GeneratedImage? get _selectedImage => _findById(_selectedImageId);

  void _onImagesChanged({bool isInitialSetup = false}) {
    final imageList = globalResultImages.value.reversed.toList();
    final imageIds = imageList.map((i) => i.id).toList();

    final liveUrls = imageList.map((i) => i.imageUrl).toSet();
    _imageCache.removeWhere((key, value) => !liveUrls.contains(key));
    for (final image in imageList) {
      if (_isBase64DataUrl(image.imageUrl) && !_imageCache.containsKey(image.imageUrl)) {
        try {
          _imageCache[image.imageUrl] = base64Decode(_extractBase64Data(image.imageUrl));
        } catch (e) {
          debugPrint("Failed to decode base64 image: $e");
        }
      }
    }

    String? newSelectedId = _selectedImageId;
    if (isInitialSetup) {
      newSelectedId = imageIds.isNotEmpty ? imageIds.first : null;
    } else if (_selectedImageId != null && !imageIds.contains(_selectedImageId)) {
      final oldList = _lastKnownImageIds;
      final deletedIndex = oldList.indexOf(_selectedImageId!);

      if (deletedIndex != -1 && oldList.length > 1) {
        if (deletedIndex < oldList.length - 1) {
          newSelectedId = oldList[deletedIndex + 1];
        } else {
          newSelectedId = oldList[deletedIndex - 1];
        }
      } else {
        newSelectedId = imageIds.isNotEmpty ? imageIds.first : null;
      }
      if (!imageIds.contains(newSelectedId)) {
        newSelectedId = imageIds.isNotEmpty ? imageIds.first : null;
      }
    }

    if (isInitialSetup) {
      setState(() {
        _selectedImageId = newSelectedId;
      });
    }

    if (mounted && newSelectedId != _selectedImageId) {
      setState(() {
        _selectedImageId = newSelectedId;
      });
    }

    _lastKnownImageIds = imageIds;
  }

  bool _isBase64DataUrl(String url) {
    return url.startsWith('data:image/');
  }

  String _extractBase64Data(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex != -1) {
      return dataUrl.substring(commaIndex + 1);
    }
    return dataUrl;
  }

  Future<void> _saveSelectedImage() async {
    final selected = _selectedImage;
    if (selected == null || _isSaving) return;

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    try {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }
        // Proceeding anyway as some Android versions handle permissions differently
      }

      const downloadsPath = '/storage/emulated/0/Download';
      final fileName = 'generated_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savePath = '$downloadsPath/$fileName';

      if (_isBase64DataUrl(selected.imageUrl)) {
        final bytes = _imageCache[selected.imageUrl] ?? base64Decode(_extractBase64Data(selected.imageUrl));
        final file = File(savePath);
        await file.writeAsBytes(bytes);
      } else {
        final bytes = await fetchImageBytes(selected.imageUrl);
        final file = File(savePath);
        await file.writeAsBytes(bytes);
      }

      messenger.showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text('Saved to Downloads'),
            ],
          ),
          // Follows the active backend's accent instead of a fixed green.
          backgroundColor: AppTheme.accentPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall * 0.8)),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _deleteSelectedImage() {
    final selected = _selectedImage;
    if (selected == null) return;
    globalResultImages.value = globalResultImages.value.where((i) => i.id != selected.id).toList();
  }

  Future<void> _showImageInfo() async {
    final selected = _selectedImage;
    if (selected == null || _isFetchingInfo) return;

    // ComfyUI has no universal PNG-info contract; show the locally-retained
    // workflow/prompt metadata instead of calling a Forge-only endpoint.
    if (selected.backend == BackendKind.comfy) {
      showMetadataModal(context, {
        if (selected.promptSnapshot?.isNotEmpty == true) 'Prompt': selected.promptSnapshot!,
        if (selected.negativePromptSnapshot?.isNotEmpty == true) 'Negative prompt': selected.negativePromptSnapshot!,
        if (selected.workflowId != null) 'Workflow': selected.workflowId!,
        if (selected.promptId != null) 'Prompt ID': selected.promptId!,
        if (selected.outputNodeId != null) 'Output node': selected.outputNodeId!,
        if (selected.comfyFilename != null) 'Filename': selected.comfyFilename!,
      });
      return;
    }

    if (!globalBackend.capabilities.metadata) return;

    setState(() => _isFetchingInfo = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      String base64Image;

      if (_isBase64DataUrl(selected.imageUrl)) {
        base64Image = _extractBase64Data(selected.imageUrl);
      } else {
        final bytes = await fetchImageBytes(selected.imageUrl);
        base64Image = base64Encode(bytes);
      }

      final responseData = await postPngInfo(base64Image);

      if (mounted) {
        final info = responseData['info'] as String?;

        if (info == null || info.isEmpty) {
          messenger.showSnackBar(const SnackBar(content: Text('No metadata found'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
          return;
        }

        final infoMap = _parseImageInfo(info);
        showMetadataModal(context, infoMap);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingInfo = false);
      }
    }
  }

  Map<String, String> _parseImageInfo(String info) {
    return parseImageInfo(info);
  }

  void _editSelectedImage() {
    final selected = _selectedImage;
    if (selected == null) return;
    globalImageToEdit.value = selected.imageUrl;
    navigateToInpaintPage();
  }

  /// Returns the selected image as bytes, or null if unavailable.
  Future<Uint8List?> _getSelectedImageBytes() async {
    final selected = _selectedImage;
    if (selected == null) return null;
    final url = selected.imageUrl;
    if (_isBase64DataUrl(url)) {
      try {
        return _imageCache[url] ?? base64Decode(_extractBase64Data(url));
      } catch (_) {
        return null;
      }
    }
    try {
      return await fetchImageBytes(url);
    } catch (_) {
      return null;
    }
  }

  void _showEditDestinationMenu() {
    if (_selectedImage == null) return;
    final parentContext = context;
    showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.glassBackground.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
          border: Border(top: BorderSide(color: AppTheme.glassBorder)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Send to',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.crop_rounded, color: AppTheme.accentPrimary),
                title: const Text('Crop', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final bytes = await _getSelectedImageBytes();
                  if (!parentContext.mounted) return;
                  if (bytes != null) {
                    showCropModal(parentContext, initialImageBytes: bytes);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_size_select_large_rounded, color: AppTheme.accentPrimary),
                title: const Text('Resize', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final bytes = await _getSelectedImageBytes();
                  if (!parentContext.mounted) return;
                  if (bytes != null) {
                    showResizeModal(parentContext, initialImageBytes: bytes);
                  }
                },
              ),
              if (globalBackend.capabilities.upscale)
                ListTile(
                  leading: Icon(Icons.auto_awesome_rounded, color: AppTheme.accentPrimary),
                  title: const Text('Upscale', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final bytes = await _getSelectedImageBytes();
                    if (!parentContext.mounted) return;
                    if (bytes != null) {
                      showUpscaleModal(parentContext, initialImageBytes: bytes);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== Widgets ===== //

  Widget _buildEmptyState() {
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsGenerating,
      builder: (context, isGenerating, child) {
        if (isGenerating) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 56, width: 56, child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.accentPrimary)),
                const SizedBox(height: 24),
                Text('Generating...', style: TextStyle(color: AppTheme.mist80, fontSize: 17, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.mist.withValues(alpha: 0.04), border: Border.all(color: AppTheme.mist10)),
                child: Icon(Icons.blur_circular_rounded, size: 40, color: AppTheme.mist18),
              ),
              const SizedBox(height: 18),
              Text('Nothing here yet', style: TextStyle(color: AppTheme.mist35, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Generated images will appear here', style: TextStyle(color: AppTheme.mist18, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainImage() {
    final selected = _selectedImage;
    if (selected == null) return const SizedBox.expand();

    // LOGIC: Check if we are comparing and have a valid input file
    final File? inputFile = globalInputImage.value;
    final bool showInput = _isComparing && inputFile != null && inputFile.existsSync();

    // The key ensures the widget rebuilds with animation when switching sources
    final imageKey = showInput ? 'input_image' : selected.id;

    return SizedBox(
        key: ValueKey<String>(imageKey),
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. The Image Layer
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: showInput ? Image.file(inputFile, fit: BoxFit.contain, gaplessPlayback: true) : _buildResultImageWidget(selected.imageUrl),
            ),

            // 2. The Status Badge (Visual Feedback)
            Positioned(
              top: 12,
              left: 12,
              child: AnimatedOpacity(
                opacity: _isComparing ? 1.0 : (globalActiveBackendKind.value == BackendKind.comfy ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: showInput ? AppTheme.warning.withValues(alpha: 0.9) : (selected.backend == BackendKind.comfy ? AppTheme.accentSecondary.withValues(alpha: 0.85) : AppTheme.accentPrimary.withValues(alpha: 0.8)),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    boxShadow: [BoxShadow(color: AppTheme.ink.withValues(alpha: 0.5), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      Icon(showInput ? Icons.input : Icons.image, color: AppTheme.ink, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        showInput ? 'INPUT SOURCE' : (selected.backend == BackendKind.comfy ? 'COMFYUI' : 'GENERATED RESULT'),
                        style: TextStyle(color: AppTheme.ink, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildResultImageWidget(String url) {
    if (_isBase64DataUrl(url)) {
      if (_imageCache[url] != null) {
        return Image.memory(_imageCache[url]!, fit: BoxFit.contain, gaplessPlayback: true);
      }
      // Attempt decode on fly if not cached
      try {
        return Image.memory(base64Decode(_extractBase64Data(url)), fit: BoxFit.contain, gaplessPlayback: true);
      } catch (e) {
        return const Icon(Icons.broken_image, color: Colors.white24);
      }
    } else {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, __) => Center(child: CircularProgressIndicator(color: AppTheme.accentPrimary)),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24),
      );
    }
  }

  /// The full result set as a glass grid below the hero - tapping a cell
  /// just changes what the hero shows, it doesn't navigate anywhere.
  Widget _buildImageGrid(List<GeneratedImage> imageList) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Row(
              children: [
                Text('ALL RESULTS', style: AppTheme.eyebrow),
                const SizedBox(width: 8),
                Text('${imageList.length}', style: TextStyle(color: AppTheme.mist35, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: imageList.length,
            itemBuilder: (context, index) {
              final image = imageList[index];
              final isSelected = image.id == _selectedImageId;
              return GestureDetector(
                onTap: () => setState(() => _selectedImageId = image.id),
                child: AnimatedContainer(
                  duration: AppTheme.durationFast,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(color: isSelected ? AppTheme.accentPrimary : AppTheme.glassBorderLight, width: isSelected ? 2 : 1),
                    boxShadow: isSelected ? AppTheme.glowPrimary(intensity: 0.3) : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall - 1),
                    child: _isBase64DataUrl(image.imageUrl)
                        ? (_imageCache[image.imageUrl] != null
                              ? Image.memory(_imageCache[image.imageUrl]!, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 220)
                              : Container(color: AppTheme.ink3))
                        : CachedNetworkImage(imageUrl: image.imageUrl, fit: BoxFit.cover, memCacheWidth: 220),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // === UPDATED DOCK ===
  Widget _buildActionButtons() {
    final selected = _selectedImage;
    final hasImage = selected != null;
    final hasInput = globalInputImage.value != null; // Check global variable

    return GlassContainer(
      margin: const EdgeInsets.only(top: 16, bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      borderRadius: AppTheme.radiusLarge,
      blurred: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Save Button
          Expanded(
            flex: 2,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: hasImage ? AppTheme.gradientPrimary : LinearGradient(colors: [AppTheme.ink3, AppTheme.ink2]),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                boxShadow: hasImage ? AppTheme.glowPrimary(intensity: 0.3) : [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  onTap: (hasImage && !_isSaving) ? _saveSelectedImage : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSaving) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppTheme.ink, strokeWidth: 2)) else Icon(Icons.download_rounded, color: AppTheme.ink, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        _isSaving ? 'Saving' : 'Save',
                        style: TextStyle(color: hasImage ? AppTheme.ink : AppTheme.mist35, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Compare Button with Hold Interaction
          Expanded(
            child: Listener(
              // Trigger compare state on press down
              onPointerDown: (hasImage && hasInput) ? (_) => setState(() => _isComparing = true) : null,
              // Reset on release or cancel
              onPointerUp: (_) => setState(() => _isComparing = false),
              onPointerCancel: (_) => setState(() => _isComparing = false),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  onTap: (hasImage && hasInput) ? () {} : null, // Needed for ripple
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    height: 50,
                    decoration: _isComparing
                        ? BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.5)),
                          )
                        : null,
                    child: Icon(
                      Icons.compare,
                      color: (hasImage && hasInput) ? (_isComparing ? AppTheme.warning : AppTheme.mist) : AppTheme.mist10,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Container(width: 1, height: 24, color: AppTheme.mist10, margin: const EdgeInsets.symmetric(horizontal: 4)),

          // Edit Button (tap = inpaint, long-press = choose Crop or Resize)
          _buildIconAction(Icons.auto_fix_high, 'Edit', hasImage ? _editSelectedImage : null, onLongPress: hasImage ? _showEditDestinationMenu : null),

          // Info Button
          _buildIconAction(Icons.info_outline, 'Info', (hasImage && !_isFetchingInfo) ? _showImageInfo : null, isLoading: _isFetchingInfo),

          // Delete Button
          _buildIconAction(Icons.delete_outline, 'Delete', hasImage ? _deleteSelectedImage : null, isDestructive: true),
        ],
      ),
    );
  }

  Widget _buildIconAction(IconData icon, String tooltip, VoidCallback? onTap, {VoidCallback? onLongPress, bool isLoading = false, bool isDestructive = false}) {
    final isEnabled = onTap != null || onLongPress != null;
    final color = isDestructive ? AppTheme.error : AppTheme.mist;

    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              height: 50,
              child: Center(
                child: isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color)) : Icon(icon, color: isEnabled ? color : AppTheme.mist10, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GeneratedImage>>(
      valueListenable: globalResultImages,
      builder: (context, images, child) {
        final imageList = images.reversed.toList();

        return Column(
          children: [
            const SizedBox(height: 16),
            // Hero card - the selected image, full height, glass-framed.
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 420,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(color: imageList.isNotEmpty ? AppTheme.accentPrimary.withValues(alpha: 0.3) : AppTheme.glassBorder, width: 1.5),
                boxShadow: imageList.isNotEmpty ? [BoxShadow(color: AppTheme.accentPrimary.withValues(alpha: 0.15), blurRadius: 24)] : [],
              ),
              padding: const EdgeInsets.all(10),
              child: imageList.isEmpty ? _buildEmptyState() : _buildMainImage(),
            ),

            // Action Dock
            if (imageList.isNotEmpty) _buildActionButtons(),

            // Full result set, as a grid
            if (imageList.isNotEmpty) _buildImageGrid(imageList),

            // Bottom Padding for scrolling
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
