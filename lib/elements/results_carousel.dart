// results_carousel.dart:
// ==================== Enhanced Results Carousel ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // Required for Uint8List
import 'dart:ui'; // Required for ImageFilter
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

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

  final Map<String, Uint8List> _imageCache = {};
  List<String> _lastKnownImageList = [];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    globalResultImages.addListener(_onImagesChanged);
    _onImagesChanged(isInitialSetup: true);
  }

  @override
  void dispose() {
    globalResultImages.removeListener(_onImagesChanged);
    super.dispose();
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

    // Subtle feedback instead of blocking snackbar
    messenger.clearSnackBars();

    try {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }
        throw Exception('Storage permission denied.');
      }

      final downloadsPath = '/storage/emulated/0/Download';
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
        await Dio().download(_selectedImageUrl!, savePath);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              const Text('Saved to Downloads'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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

    // Optional: Add a confirmation or undo capability could go here,
    // but for now keeping it snappy.
    final currentSet = Set<String>.from(globalResultImages.value);
    currentSet.remove(_selectedImageUrl!);
    globalResultImages.value = currentSet;
  }

  /// UPDATED: Fetch and display image info in a Modal Bottom Sheet
  Future<void> _showImageInfo() async {
    if (_selectedImageUrl == null || _isFetchingInfo) return;

    setState(() => _isFetchingInfo = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      String base64Image;

      if (_isBase64DataUrl(_selectedImageUrl!)) {
        base64Image = _extractBase64Data(_selectedImageUrl!);
      } else {
        final response = await Dio().get<List<int>>(
          _selectedImageUrl!,
          options: Options(responseType: ResponseType.bytes),
        );
        base64Image = base64Encode(response.data!);
      }

      final response = await Dio().post(
        'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/png-info',
        data: {'image': base64Image},
      );

      if (mounted) {
        final info = response.data['info'] as String?;

        if (info == null || info.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('No metadata found in this image'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        final infoMap = _parseImageInfo(info);

        // Show the info in the new Modal design
        _showInfoModal(infoMap);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error fetching info: $e'),
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

  /// NEW: The Modal Bottom Sheet implementation for Image Info
  void _showInfoModal(Map<String, String> infoMap) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.7, // Takes up 70% of screen
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24.0),
                topRight: Radius.circular(24.0),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
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
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.cyan.shade400.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.data_object_rounded,
                              color: Colors.cyan.shade400,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Generation Metadata',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (infoMap['prompt'] != null) ...[
                          _buildModernInfoSection(
                            'Positive Prompt',
                            infoMap['prompt']!,
                            Icons.add_circle_outline_rounded,
                            Colors.green.shade300,
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (infoMap['negativePrompt'] != null) ...[
                          _buildModernInfoSection(
                            'Negative Prompt',
                            infoMap['negativePrompt']!,
                            Icons.remove_circle_outline_rounded,
                            Colors.red.shade300,
                          ),
                          const SizedBox(height: 20),
                        ],
                        Text(
                          'Parameters',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoGrid(infoMap),
                        const SizedBox(height: 20), // Bottom padding
                      ],
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

  Map<String, String> _parseImageInfo(String info) {
    final map = <String, String>{};
    final lines = info.split('\n');
    String? currentPrompt;
    String? currentNegativePrompt;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('Negative prompt:')) {
        currentNegativePrompt = line
            .substring('Negative prompt:'.length)
            .trim();
        continue;
      }

      if (line.contains(':') && (line.contains(',') || i == lines.length - 1)) {
        final parts = line.split(',');
        for (final part in parts) {
          final keyValue = part.trim().split(':');
          if (keyValue.length == 2) {
            map[keyValue[0].trim()] = keyValue[1].trim();
          }
        }
      } else if (currentNegativePrompt != null) {
        currentNegativePrompt += ' $line';
      } else {
        currentPrompt =
            (currentPrompt ?? '') + (currentPrompt != null ? ' ' : '') + line;
      }
    }

    if (currentPrompt != null) map['prompt'] = currentPrompt;
    if (currentNegativePrompt != null)
      map['negativePrompt'] = currentNegativePrompt;

    return map;
  }

  /// NEW: Improved Section styling for the modal
  Widget _buildModernInfoSection(
    String label,
    String value,
    IconData icon,
    Color accentColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(Map<String, String> infoMap) {
    final items = <Widget>[];
    final paramOrder = {
      'Steps': 'Steps',
      'Sampler': 'Sampler',
      'CFG scale': 'CFG',
      'Seed': 'Seed',
      'Model': 'Checkpoint',
      'Model hash': 'Hash',
      'VAE': 'VAE',
    };

    for (final entry in paramOrder.entries) {
      if (infoMap.containsKey(entry.key)) {
        items.add(_buildInfoItem(entry.value, infoMap[entry.key]!));
      }
    }

    // Add others
    for (final entry in infoMap.entries) {
      if (!paramOrder.containsKey(entry.key) &&
          entry.key != 'prompt' &&
          entry.key != 'negativePrompt') {
        items.add(_buildInfoItem(entry.key, entry.value));
      }
    }

    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }

  Widget _buildInfoItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _editSelectedImage() {
    if (_selectedImageUrl == null) return;
    globalImageToEdit.value = _selectedImageUrl;
    globalPageIndex.value = 0;
  }

  // ===== Class Widgets ===== //

  Widget _buildEmptyState() {
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsGenerating,
      builder: (context, isGenerating, child) {
        if (isGenerating) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.cyan.shade400.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.cyan.shade400.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: CircularProgressIndicator(color: Colors.cyan.shade300),
                ),
                const SizedBox(height: 24),
                Text(
                  'Creating Masterpiece...',
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
                Icons.image_search_rounded,
                size: 48,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),
              Text(
                'No Results Yet',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
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
    if (_selectedImageUrl == null) {
      return const Expanded(child: Center());
    }

    return Expanded(
      child: Container(
        key: ValueKey<String>(_selectedImageUrl!),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _isBase64DataUrl(_selectedImageUrl!)
              ? (_imageCache[_selectedImageUrl!] != null
                    ? Image.memory(
                        _imageCache[_selectedImageUrl!]!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      )
                    : const Icon(Icons.error))
              : CachedNetworkImage(
                  imageUrl: _selectedImageUrl!,
                  fit: BoxFit.contain,
                  placeholder: (context, url) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
        ),
      ),
    );
  }

  Widget _buildImageThumbnails(List<String> imageList) {
    return Container(
      height: 90,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10),
        itemCount: imageList.length,
        itemBuilder: (context, index) {
          final imageUrl = imageList[index];
          final isSelected = imageUrl == _selectedImageUrl;
          return GestureDetector(
            onTap: () => setState(() => _selectedImageUrl = imageUrl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              width: isSelected ? 70 : 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? Colors.cyan.shade400 : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.cyan.shade400.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
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

  /// UPDATED: Modern Floating Dock for Actions
  Widget _buildActionButtons() {
    final hasImage = _selectedImageUrl != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Save - Primary Action (Large with Text)
          Expanded(
            flex: 2,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: hasImage
                    ? LinearGradient(
                        colors: [Colors.cyan.shade600, Colors.cyan.shade400],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [Colors.grey.shade700, Colors.grey.shade600],
                      ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: hasImage
                    ? [
                        BoxShadow(
                          color: Colors.cyan.shade500.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Secondary Action Group
          _buildIconAction(
            icon: Icons.auto_fix_high_rounded,
            tooltip: 'Edit in Inpaint',
            onTap: hasImage ? _editSelectedImage : null,
          ),
          _buildIconAction(
            icon: Icons.info_outline_rounded,
            tooltip: 'Metadata',
            isLoading: _isFetchingInfo,
            onTap: (hasImage && !_isFetchingInfo) ? _showImageInfo : null,
          ),

          Container(
            height: 24,
            width: 1,
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),

          // Destructive Action
          _buildIconAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            color: Colors.red.shade400,
            onTap: hasImage ? _deleteSelectedImage : null,
          ),
        ],
      ),
    );
  }

  Widget _buildIconAction({
    required IconData icon,
    required VoidCallback? onTap,
    String? tooltip,
    Color? color,
    bool isLoading = false,
  }) {
    final isEnabled = onTap != null;
    final contentColor = isEnabled
        ? (color ?? Colors.white.withValues(alpha: 0.8))
        : Colors.white.withValues(alpha: 0.2);

    return Expanded(
      flex: 1,
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: contentColor,
                        ),
                      )
                    : Icon(icon, color: contentColor, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: globalResultImages,
      builder: (context, imageSet, child) {
        final imageList = imageSet.toList().reversed.toList();

        return Column(
          children: [
            Container(
              height: 600,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.grey.shade800.withValues(alpha: 0.6),
                    Colors.grey.shade900.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1.5,
                ),
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
            // The new Dock Style buttons
            if (imageList.isNotEmpty) _buildActionButtons(),
          ],
        );
      },
    );
  }
}
