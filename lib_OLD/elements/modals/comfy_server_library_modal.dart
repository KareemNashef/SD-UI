// ==================== Comfy Server Library Modal ==================== //
//
// Browses ComfyUI's output folder via the PanicTitan/ComfyUI-Gallery addon
// (see ComfyGalleryClient for endpoint details, why this fetches everything
// in one call, and why that response can legitimately be huge) and lets the
// user "bring back" images into the local results carousel.
//
// The server this was built against went from a few nested folders to
// 11,000+ flat images, which killed two things the earlier version relied
// on: folder browsing (nothing to browse anymore) and a GridView.builder
// nested inside a SingleChildScrollView with shrinkWrap - shrinkWrap forces
// the grid to lay out (i.e. build) every single item up front to measure
// its own height, so it was building all 11,000 tiles immediately instead
// of virtualizing. This version drops folder UI entirely, groups images by
// day into a flat scrollable list (ScrollablePositionedList - properly
// virtualized, and unlike a plain ListView it can jump to an arbitrary
// index without building everything in between), and adds a date picker
// that jumps straight to a day instead of requiring the user to scroll.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/logic/comfy/comfy_gallery_client.dart';
import 'package:sd_companion/logic/globals.dart';

void showComfyServerLibraryModal(BuildContext context) {
  GlassModal.show(
    context,
    heightFactor: 0.92,
    child: const _ComfyServerLibraryModal(),
  );
}

// ===== Row model for the flat, day-grouped scroll list ===== //

sealed class _GalleryRow {}

class _DateHeaderRow extends _GalleryRow {
  final DateTime? day; // null = "Unknown date" bucket
  final int count;
  _DateHeaderRow(this.day, this.count);
}

class _ImagesRow extends _GalleryRow {
  final List<ComfyGalleryImage> images; // 1-3, left-aligned
  _ImagesRow(this.images);
}

const int _kColumns = 3;

class _ComfyServerLibraryModal extends StatefulWidget {
  const _ComfyServerLibraryModal();

  @override
  State<_ComfyServerLibraryModal> createState() => _ComfyServerLibraryModalState();
}

class _ComfyServerLibraryModalState extends State<_ComfyServerLibraryModal> {
  final ComfyGalleryClient _client = ComfyGalleryClient();
  final TextEditingController _searchController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();

  bool _loading = true;
  String? _error;
  List<ComfyGalleryImage> _images = const [];
  List<_GalleryRow> _rows = const [];
  Map<DateTime?, int> _dayRowIndex = const {}; // day -> its header's row index
  final Set<String> _selectedKeys = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _search = _searchController.text.trim().toLowerCase();
        _rebuildRows();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _client.dispose();
    super.dispose();
  }

  String _keyFor(ComfyGalleryImage image) => '${image.subfolder}/${image.filename}';

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final images = await _client.fetchAll(globalComfyBackend.profile, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _images = images;
        _rebuildRows();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== Grouping / filtering ===== //

  bool get _isSearching => _search.isNotEmpty;

  List<ComfyGalleryImage> get _visibleImages {
    if (!_isSearching) return _images;
    return _images.where((img) {
      final haystack = '${img.filename} ${img.subfolder}'.toLowerCase();
      return haystack.contains(_search);
    }).toList();
  }

  /// Groups the (already newest-first) visible images by calendar day and
  /// flattens into header + up-to-3-image rows for the scroll list, along
  /// with an index of each day's header row for jump-to-date.
  void _rebuildRows() {
    final images = _visibleImages;
    final byDay = <DateTime, List<ComfyGalleryImage>>{};
    final undated = <ComfyGalleryImage>[];
    for (final img in images) {
      final created = img.createdAt;
      if (created == null) {
        undated.add(img);
        continue;
      }
      final day = DateTime(created.year, created.month, created.day);
      byDay.putIfAbsent(day, () => []).add(img);
    }

    final rows = <_GalleryRow>[];
    final dayIndex = <DateTime?, int>{};
    // Insertion order into byDay follows `images`, which is already
    // newest-first, so this iteration is too - no extra sort needed.
    for (final entry in byDay.entries) {
      dayIndex[entry.key] = rows.length;
      rows.add(_DateHeaderRow(entry.key, entry.value.length));
      for (var i = 0; i < entry.value.length; i += _kColumns) {
        rows.add(_ImagesRow(entry.value.sublist(i, (i + _kColumns).clamp(0, entry.value.length))));
      }
    }
    if (undated.isNotEmpty) {
      dayIndex[null] = rows.length;
      rows.add(_DateHeaderRow(null, undated.length));
      for (var i = 0; i < undated.length; i += _kColumns) {
        rows.add(_ImagesRow(undated.sublist(i, (i + _kColumns).clamp(0, undated.length))));
      }
    }

    _rows = rows;
    _dayRowIndex = dayIndex;
  }

  Future<void> _jumpToDate() async {
    final days = _dayRowIndex.keys.whereType<DateTime>().toList(); // already newest-first
    if (days.isEmpty) return;
    final newest = days.first;
    final oldest = days.last;
    final picked = await showDatePicker(
      context: context,
      initialDate: newest,
      firstDate: oldest,
      lastDate: newest,
    );
    if (picked == null) return;
    final target = DateTime(picked.year, picked.month, picked.day);
    // Nearest available day on/before the picked date; falls back to the
    // oldest available day if everything is after it.
    DateTime match = days.last;
    for (final d in days) {
      if (!d.isAfter(target)) {
        match = d;
        break;
      }
    }
    final index = _dayRowIndex[match];
    if (index == null) return;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _toggleSelect(ComfyGalleryImage image) {
    setState(() {
      final key = _keyFor(image);
      if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
    });
  }

  void _bringBackSelected() {
    final profile = globalComfyBackend.profile;
    final selected = _images.where((img) => _selectedKeys.contains(_keyFor(img))).toList();
    if (selected.isEmpty) return;
    globalResultImages.value = [
      ...globalResultImages.value,
      ...selected.map((img) => img.toGeneratedImage(profile)),
    ];
    final count = selected.length;
    setState(() => _selectedKeys.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $count image${count == 1 ? '' : 's'} to Results'),
        backgroundColor: AppTheme.comfyAccentPrimary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _previewImage(ComfyGalleryImage image) {
    final profile = globalComfyBackend.profile;
    final details = [
      if (image.resolution != null) image.resolution!,
      if (image.sizeLabel != null) image.sizeLabel!,
    ].join(' · ');
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: CachedNetworkImage(imageUrl: image.viewUri(profile).toString(), fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              image.filename,
              style: const TextStyle(color: AppTheme.mist, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(details, style: const TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    globalResultImages.value = [
                      ...globalResultImages.value,
                      image.toGeneratedImage(profile),
                    ];
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Added to Results'),
                        backgroundColor: AppTheme.comfyAccentPrimary,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.comfyAccentPrimary),
                  icon: const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.mist, size: 18),
                  label: const Text('Add to Results', style: TextStyle(color: AppTheme.mist)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== Widgets ===== //

  String _dayLabel(DateTime? day) {
    if (day == null) return 'Unknown date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final label = '${months[day.month - 1]} ${day.day}';
    return day.year == now.year ? label : '$label, ${day.year}';
  }

  Widget _buildHeaderRow(_DateHeaderRow row) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Text(
            _dayLabel(row.day),
            style: const TextStyle(color: AppTheme.mist, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AppTheme.mist.withValues(alpha: 0.08))),
          const SizedBox(width: 10),
          Text('${row.count}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildImagesRow(_ImagesRow row, double tileSize) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < _kColumns; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: i < row.images.length ? _buildImageTile(row.images[i]) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageTile(ComfyGalleryImage image) {
    final profile = globalComfyBackend.profile;
    final selected = _selectedKeys.contains(_keyFor(image));
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _toggleSelect(image),
        onLongPress: () => _previewImage(image),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.black26,
                child: CachedNetworkImage(
                  imageUrl: image.viewUri(profile).toString(),
                  fit: BoxFit.cover,
                  memCacheWidth: 240,
                  placeholder: (_, __) => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: selected ? Border.all(color: AppTheme.comfyAccentPrimary, width: 3) : null,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppTheme.comfyAccentPrimary : Colors.black.withValues(alpha: 0.5),
                  border: Border.all(color: AppTheme.mist.withValues(alpha: 0.6), width: 1),
                ),
                child: selected ? const Icon(Icons.check_rounded, color: AppTheme.mist, size: 14) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    if (_selectedKeys.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppTheme.glassBackground,
        border: Border(top: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedKeys.length} selected',
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedKeys.clear()),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _bringBackSelected,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.comfyAccentPrimary),
              icon: const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.mist, size: 18),
              label: Text('Add ${_selectedKeys.length} to Results', style: const TextStyle(color: AppTheme.mist)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDatedImages = _dayRowIndex.keys.whereType<DateTime>().isNotEmpty;
    return Column(
      children: [
        GlassHeader(
          title: 'Server Library',
          subtitle: _isSearching ? '${_visibleImages.length} match' : '${_images.length} images on server',
          icon: Icons.cloud_download_rounded,
          iconColor: AppTheme.comfyAccentPrimary,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isSearching)
                IconButton(
                  tooltip: 'Jump to date',
                  onPressed: hasDatedImages ? _jumpToDate : null,
                  icon: const Icon(Icons.calendar_month_rounded, color: Colors.white54),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : () => _load(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: GlassInput(
            controller: _searchController,
            hintText: 'Search by filename...',
            prefixIcon: Icons.search,
            accentColor: AppTheme.comfyAccentPrimary,
          ),
        ),
        Expanded(child: _buildContent()),
        _buildSelectionBar(),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Loading the full server gallery - this can take a while on a large output folder…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 40),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: () => _load(forceRefresh: true), child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 48, color: AppTheme.mist.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              _isSearching ? 'No images match "$_search"' : 'No generated images found on the server yet',
              style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.4), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = (constraints.maxWidth - 32 - 8 * (_kColumns - 1)) / _kColumns;
        return ScrollablePositionedList.builder(
          itemScrollController: _itemScrollController,
          physics: const BouncingScrollPhysics(),
          itemCount: _rows.length,
          itemBuilder: (context, index) {
            final row = _rows[index];
            return switch (row) {
              _DateHeaderRow() => _buildHeaderRow(row),
              _ImagesRow() => _buildImagesRow(row, tileSize),
            };
          },
        );
      },
    );
  }
}
