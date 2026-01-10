// ==================== Enhanced Results Carousel ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sd_companion/elements/modals/metadata_modal.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/utils/image_metadata_parser.dart';
// Local imports - Widgets
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// ========== Enhanced Results Carousel Class ========== //

class ResultsCarousel extends StatefulWidget {
  const ResultsCarousel({super.key});

  @override
  State<ResultsCarousel> createState() => _ResultsCarouselState();
}

class _ResultsCarouselState extends State<ResultsCarousel> {
  // ===== Class Variables ===== //

  String? _selectedImageUrl;
  bool _isSaving = false;
  bool _isFetchingInfo = false;

  bool _isComparing = false;

  final Map<String, Uint8List> _imageCache = {};
  List<String> _lastKnownImageList = [];

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

  void _onImagesChanged({bool isInitialSetup = false}) {
    final imageSet = globalResultImages.value;
    final imageList = imageSet.toList().reversed.toList();

    _imageCache.removeWhere((key, value) => !imageSet.contains(key));
    for (final url in imageList) {
      if (_isBase64DataUrl(url) && !_imageCache.containsKey(url)) {
        try {
          _imageCache[url] = base64Decode(_extractBase64Data(url));
        } catch (e) {
          debugPrint("Failed to decode base64 image: $e");
        }
      }
    }

    String? newSelectedImage = _selectedImageUrl;
    if (isInitialSetup) {
      newSelectedImage = imageList.isNotEmpty ? imageList.first : null;
    } else if (_selectedImageUrl != null &&
        !imageSet.contains(_selectedImageUrl)) {
      final oldList = _lastKnownImageList;
      final deletedIndex = oldList.indexOf(_selectedImageUrl!);

      if (deletedIndex != -1 && oldList.length > 1) {
        if (deletedIndex < oldList.length - 1) {
          newSelectedImage = oldList[deletedIndex + 1];
        } else {
          newSelectedImage = oldList[deletedIndex - 1];
        }
      } else {
        newSelectedImage = imageList.isNotEmpty ? imageList.first : null;
      }
    }

    if (isInitialSetup) {
      setState(() {
        _selectedImageUrl = newSelectedImage;
      });
    }

    if (mounted && newSelectedImage != _selectedImageUrl) {
      setState(() {
        _selectedImageUrl = newSelectedImage;
      });
    }

    _lastKnownImageList = imageList;
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
    if (_selectedImageUrl == null || _isSaving) return;

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
      final fileName =
          'generated_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savePath = '$downloadsPath/$fileName';

      if (_isBase64DataUrl(_selectedImageUrl!)) {
        final bytes =
            _imageCache[_selectedImageUrl!] ??
            base64Decode(_extractBase64Data(_selectedImageUrl!));
        final file = File(savePath);
        await file.writeAsBytes(bytes);
      } else {
        final bytes = await fetchImageBytes(_selectedImageUrl!);
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
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall * 0.8),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _deleteSelectedImage() {
    if (_selectedImageUrl == null) return;
    final currentSet = Set<String>.from(globalResultImages.value);
    currentSet.remove(_selectedImageUrl!);
    globalResultImages.value = currentSet;
  }

  Future<void> _showImageInfo() async {
    if (_selectedImageUrl == null || _isFetchingInfo) return;

    setState(() => _isFetchingInfo = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      String base64Image;

      if (_isBase64DataUrl(_selectedImageUrl!)) {
        base64Image = _extractBase64Data(_selectedImageUrl!);
      } else {
        final bytes = await fetchImageBytes(_selectedImageUrl!);
        base64Image = base64Encode(bytes);
      }

      final responseData = await postPngInfo(base64Image);

      if (mounted) {
        final info = responseData['info'] as String?;

        if (info == null || info.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('No metadata found'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        final infoMap = _parseImageInfo(info);
        showMetadataModal(context, infoMap);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
    if (_selectedImageUrl == null) return;
    globalImageToEdit.value = _selectedImageUrl;
    globalPageIndex.value = 0;
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
                const SizedBox(
                  height: 60,
                  width: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.accentPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Generating...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 64,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 16),
              Text(
                'Gallery is empty',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainImage() {
    if (_selectedImageUrl == null) return const Expanded(child: Center());

    // LOGIC: Check if we are comparing and have a valid input file
    final File? inputFile = globalInputImage.value;
    final bool showInput =
        _isComparing && inputFile != null && inputFile.existsSync();

    // The key ensures the widget rebuilds with animation when switching sources
    final imageKey = showInput ? 'input_image' : _selectedImageUrl!;

    return Expanded(
      child: SizedBox(
        key: ValueKey<String>(imageKey),
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. The Image Layer
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: showInput
                  ? Image.file(
                      inputFile,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    )
                  : _buildResultImageWidget(_selectedImageUrl!),
            ),

            // 2. The Status Badge (Visual Feedback)
            Positioned(
              top: 12,
              left: 12,
              child: AnimatedOpacity(
                opacity: _isComparing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: showInput
                        ? AppTheme.warning.withValues(alpha: 0.9)
                        : AppTheme.accentPrimary.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        showInput ? Icons.input : Icons.image,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        showInput ? 'INPUT SOURCE' : 'GENERATED RESULT',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultImageWidget(String url) {
    if (_isBase64DataUrl(url)) {
      if (_imageCache[url] != null) {
        return Image.memory(
          _imageCache[url]!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      }
      // Attempt decode on fly if not cached
      try {
        return Image.memory(
          base64Decode(_extractBase64Data(url)),
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      } catch (e) {
        return const Icon(Icons.broken_image, color: Colors.white24);
      }
    } else {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
          child: CircularProgressIndicator(color: AppTheme.accentPrimary),
        ),
        errorWidget: (_, __, ___) =>
            const Icon(Icons.broken_image, color: Colors.white24),
      );
    }
  }

  Widget _buildImageThumbnails(List<String> imageList) {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: imageList.length,
        itemBuilder: (context, index) {
          final imageUrl = imageList[index];
          final isSelected = imageUrl == _selectedImageUrl;
          return GestureDetector(
            onTap: () => setState(() => _selectedImageUrl = imageUrl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              width: isSelected ? 56 : 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.accentPrimary
                      : AppTheme.glassBorderLight,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? AppTheme.glowPrimary(intensity: 0.3)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall * 0.5),
                child: _isBase64DataUrl(imageUrl)
                    ? (_imageCache[imageUrl] != null
                          ? Image.memory(
                              _imageCache[imageUrl]!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Container(color: Colors.grey.shade900))
                    : CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
              ),
            ),
          );
        },
      ),
    );
  }

  // === UPDATED DOCK ===
  Widget _buildActionButtons() {
    final hasImage = _selectedImageUrl != null;
    final hasInput = globalInputImage.value != null; // Check global variable

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.glassBackground,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Save Button
          Expanded(
            flex: 2,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: hasImage
                    ? AppTheme.gradientPrimary
                    : LinearGradient(
                        colors: [Colors.grey.shade800, Colors.grey.shade700],
                      ),
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
                      if (_isSaving)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _isSaving ? 'Saving' : 'Save',
                        style: TextStyle(
                          color: hasImage ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // [NEW] Compare Button with Hold Interaction
          Expanded(
            child: Listener(
              // Trigger compare state on press down
              onPointerDown: (hasImage && hasInput)
                  ? (_) => setState(() => _isComparing = true)
                  : null,
              // Reset on release or cancel
              onPointerUp: (_) => setState(() => _isComparing = false),
              onPointerCancel: (_) => setState(() => _isComparing = false),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  onTap: (hasImage && hasInput)
                      ? () {}
                      : null, // Needed for ripple
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    height: 50,
                    decoration: _isComparing
                        ? BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMedium,
                            ),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.5),
                            ),
                          )
                        : null,
                    child: Icon(
                      Icons.compare,
                      // If holding, turn Amber. If disabled, turn gray.
                      color: (hasImage && hasInput)
                          ? (_isComparing ? Colors.amber : Colors.white)
                          : Colors.white12,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Container(
            width: 1,
            height: 24,
            color: Colors.white10,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),

          // Edit Button
          _buildIconAction(
            Icons.auto_fix_high,
            'Edit',
            hasImage ? _editSelectedImage : null,
          ),

          // Info Button
          _buildIconAction(
            Icons.info_outline,
            'Info',
            (hasImage && !_isFetchingInfo) ? _showImageInfo : null,
            isLoading: _isFetchingInfo,
          ),

          // Delete Button
          _buildIconAction(
            Icons.delete_outline,
            'Delete',
            hasImage ? _deleteSelectedImage : null,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildIconAction(
    IconData icon,
    String tooltip,
    VoidCallback? onTap, {
    bool isLoading = false,
    bool isDestructive = false,
  }) {
    final isEnabled = onTap != null;
    final color = isDestructive ? Colors.red.shade400 : Colors.white;

    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 50,
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(
                        icon,
                        color: isEnabled ? color : Colors.white12,
                        size: 24,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: globalResultImages,
      builder: (context, imageSet, child) {
        final imageList = imageSet.toList().reversed.toList();

        return Column(
          children: [
            const SizedBox(height: 16), // Increased top spacing
            // Main Image Card
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 550,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(
                  color: imageList.isNotEmpty
                      ? AppTheme.accentPrimary.withValues(alpha: 0.3)
                      : AppTheme.glassBorder,
                  width: 1.5,
                ),
                boxShadow: imageList.isNotEmpty
                    ? [
                        BoxShadow(
                          color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                          blurRadius: 20,
                        ),
                      ]
                    : [],
              ),
              child: imageList.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        _buildMainImage(),
                        _buildImageThumbnails(imageList),
                      ],
                    ),
            ),

            // Action Dock
            if (imageList.isNotEmpty) _buildActionButtons(),

            // Bottom Padding for scrolling
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
