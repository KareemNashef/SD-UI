// ==================== Enhanced Results Carousel ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // Required for Uint8List
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

  /// FIX: A cache to hold the decoded image bytes.
  /// The key is the full base64 data URL, the value is the decoded bytes.
  /// This prevents decoding the same image over and over again.
  final Map<String, Uint8List> _imageCache = {};

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    // Listen to the global notifier to react to changes.
    globalResultImages.addListener(_onImagesChanged);
    // Perform the initial setup.
    _onImagesChanged(isInitialSetup: true);
  }

  @override
  void dispose() {
    // Always remove listeners in dispose to prevent memory leaks.
    globalResultImages.removeListener(_onImagesChanged);
    super.dispose();
  }

  // ===== Class Methods ===== //

  /// FIX: This is the core of the performance improvement.
  /// It synchronizes the local state and the image cache with the global image list.
  void _onImagesChanged({bool isInitialSetup = false}) {
    final imageSet = globalResultImages.value;
    final imageList = imageSet.toList().reversed.toList();

    // Step 1: Update the image cache.
    // - Remove entries from our cache that are no longer in the global list.
    _imageCache.removeWhere((key, value) => !imageSet.contains(key));
    // - For each image, if it's base64 and not yet in our cache, decode it ONCE and store it.
    for (final url in imageList) {
      if (_isBase64DataUrl(url) && !_imageCache.containsKey(url)) {
        try {
          _imageCache[url] = base64Decode(_extractBase64Data(url));
        } catch (e) {
          // Handle potential malformed base64 strings gracefully
          debugPrint("Failed to decode base64 image: $e");
        }
      }
    }

    // Step 2: Update the selected image URL.
    String? newSelectedImage = _selectedImageUrl;
    if (isInitialSetup ||
        (_selectedImageUrl != null && !imageSet.contains(_selectedImageUrl))) {
      // If it's the first time, or the selected image was deleted,
      // select the first image in the new list (or null if empty).
      newSelectedImage = imageList.isNotEmpty ? imageList.first : null;
    }

    // Step 3: Call setState only if something has changed.
    if (mounted && newSelectedImage != _selectedImageUrl) {
      setState(() {
        _selectedImageUrl = newSelectedImage;
      });
    } else if (isInitialSetup) {
      // On initial setup, we may need to rebuild even if the selection is the same
      // to ensure the UI is in sync.
      setState(() {});
    }
  }

  /// Helper method to check if a URL is a base64 data URL
  bool _isBase64DataUrl(String url) {
    return url.startsWith('data:image/');
  }

  /// Helper method to extract base64 data from data URL
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

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Saving to Downloads...')));

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
        // Use the cached bytes if available, otherwise decode.
        final bytes =
            _imageCache[_selectedImageUrl!] ??
            base64Decode(_extractBase64Data(_selectedImageUrl!));
        final file = File(savePath);
        await file.writeAsBytes(bytes);
      } else {
        await Dio().download(_selectedImageUrl!, savePath);
      }

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Image saved to Downloads folder!'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Error saving image: $e'),
            backgroundColor: Colors.red,
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

  // ===== Class Widgets ===== //

  Widget _buildEmptyState() {
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsGenerating,
      builder: (context, isGenerating, child) {
        if (isGenerating) {
          // Show a different empty state when generating
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.purple.shade400.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.purple.shade400.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 64,
                    color: Colors.purple.shade300,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Generation in Progress',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your images will appear here when ready',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        // Default empty state
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
                  Icons.image_search_rounded,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Results Yet',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Generated images will appear here',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 48),
        const SizedBox(height: 8),
        Text(
          'Could not load image',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }

  Widget _buildMainImage() {
    if (_selectedImageUrl == null) {
      return const Expanded(child: Center());
    }

    // FIX: This widget is now much faster. It uses a ValueKey to help Flutter's
    // rendering engine, and critically, it gets the image bytes from the cache.
    // gaplessPlayback is key to preventing the flicker.
    return Expanded(
      child: Container(
        key: ValueKey<String>(
          _selectedImageUrl!,
        ), // Use a key for efficient updates
        padding: const EdgeInsets.all(8.0),
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _isBase64DataUrl(_selectedImageUrl!)
              ? (_imageCache[_selectedImageUrl!] != null
                    ? Image.memory(
                        _imageCache[_selectedImageUrl!]!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true, // IMPORTANT: Prevents flicker
                      )
                    : _buildImageError())
              : CachedNetworkImage(
                  imageUrl: _selectedImageUrl!,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Center(
                    child: CircularProgressIndicator(
                      color: Colors.purple.shade300,
                    ),
                  ),
                  errorWidget: (context, url, error) => _buildImageError(),
                ),
        ),
      ),
    );
  }

  Widget _buildImageThumbnails(List<String> imageList) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        itemCount: imageList.length,
        itemBuilder: (context, index) {
          final imageUrl = imageList[index];
          final isSelected = imageUrl == _selectedImageUrl;
          return GestureDetector(
            onTap: () {
              // This is now super fast. Just changes the selection string and rebuilds.
              setState(() {
                _selectedImageUrl = imageUrl;
              });
            },
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Colors.purple.shade400
                        : Colors.white.withValues(alpha: 0.3),
                    width: isSelected ? 3.0 : 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.purple.shade400.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
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
                                gaplessPlayback:
                                    true, // IMPORTANT: Prevents flicker
                              )
                            : Icon(Icons.error, color: Colors.red.shade700))
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: Colors.black.withValues(alpha: 0.5)),
                          errorWidget: (context, url, error) =>
                              Icon(Icons.error, color: Colors.red.shade700),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _selectedImageUrl == null || _isSaving
                  ? null
                  : _saveSelectedImage,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, color: Colors.white),
              label: Text(
                _isSaving ? 'SAVING...' : 'SAVE',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.purple.shade500,
                disabledBackgroundColor: Colors.grey.shade600,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _selectedImageUrl == null
                  ? null
                  : _deleteSelectedImage,
              icon: const Icon(Icons.delete_rounded),
              label: const Text('DELETE'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: _selectedImageUrl == null
                    ? Colors.grey.shade600
                    : Colors.red.shade400,
                side: BorderSide(
                  color: _selectedImageUrl == null
                      ? Colors.grey.shade600
                      : Colors.red.shade400.withValues(alpha: 0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    // We now use a standard ValueListenableBuilder. The heavy lifting is done in the listener.
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
                  color: Colors.white.withValues(alpha: 0.2),
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
            imageList.isEmpty ? const SizedBox.shrink() : _buildActionButtons(),
          ],
        );
      },
    );
  }
}