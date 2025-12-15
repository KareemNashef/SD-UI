// ==================== Enhanced Results Carousel ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
    messenger.clearSnackBars();

    try {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }
        // Proceeding anyway as some Android versions handle permissions differently
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
              content: Text('No metadata found'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        final infoMap = _parseImageInfo(info);
        _showInfoModal(infoMap);
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

  void _showInfoModal(Map<String, String> infoMap) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24.0),
                topRight: Radius.circular(24.0),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.data_object,
                        color: Colors.cyan.shade300,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Metadata',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
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
                            Icons.add_circle_outline,
                            Colors.green.shade300,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (infoMap['negativePrompt'] != null) ...[
                          _buildModernInfoSection(
                            'Negative Prompt',
                            infoMap['negativePrompt']!,
                            Icons.remove_circle_outline,
                            Colors.red.shade300,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          'PARAMETERS',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoGrid(infoMap),
                        const SizedBox(height: 40),
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
              Icon(icon, size: 14, color: accentColor),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
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
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
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
                SizedBox(
                  height: 60,
                  width: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.cyan.shade300,
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

    return Expanded(
      child: Container(
        key: ValueKey<String>(_selectedImageUrl!),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _isBase64DataUrl(_selectedImageUrl!)
              ? (_imageCache[_selectedImageUrl!] != null
                    ? Image.memory(
                        _imageCache[_selectedImageUrl!]!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      )
                    : const Icon(Icons.broken_image, color: Colors.white24))
              : CachedNetworkImage(
                  imageUrl: _selectedImageUrl!,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.cyan),
                  ),
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.broken_image, color: Colors.white24),
                ),
        ),
      ),
    );
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
                      ? Colors.cyan.shade400
                      : Colors.white.withValues(alpha: 0.1),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.cyan.shade500.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
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
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                    ? LinearGradient(
                        colors: [Colors.cyan.shade600, Colors.teal.shade500],
                      )
                    : LinearGradient(
                        colors: [Colors.grey.shade800, Colors.grey.shade700],
                      ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: hasImage
                    ? [
                        BoxShadow(
                          color: Colors.cyan.shade500.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
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

          // Icons Group
          _buildIconAction(
            Icons.auto_fix_high,
            'Edit',
            hasImage ? _editSelectedImage : null,
          ),
          _buildIconAction(
            Icons.info_outline,
            'Info',
            (hasImage && !_isFetchingInfo) ? _showImageInfo : null,
            isLoading: _isFetchingInfo,
          ),

          Container(
            width: 1,
            height: 24,
            color: Colors.white10,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),

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
            // Main Image Card
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 570,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(
                  color: imageList.isNotEmpty
                      ? Colors.cyan.shade900
                      : Colors.white.withValues(alpha: 0.1),
                  width: 1.5,
                ),
                boxShadow: imageList.isNotEmpty
                    ? [
                        BoxShadow(
                          color: Colors.cyan.shade900.withValues(alpha: 0.15),
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
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
