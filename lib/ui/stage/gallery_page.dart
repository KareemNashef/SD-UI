// ==================== Server Gallery ==================== //
//
// CHECKLIST 7.1: browse everything the ComfyUI server has already produced.
//
// This talks to the purpose-built `aperture_gallery` addon (comfy_addon/),
// which paginates and filters server-side and serves real thumbnails. That
// changes the shape of the problem entirely: instead of downloading the whole
// library and being clever about rendering it, the page asks for sixty
// entries at a time and draws them.
//
// A server without that addon falls back to the older `ComfyUI-Gallery`
// route, which returns everything at once - so installing the new addon is an
// upgrade rather than a requirement, and nothing regresses without it.

import 'package:flutter/material.dart';

import 'package:sd_companion/data/engines/comfy/aperture_gallery_client.dart';
import 'package:sd_companion/data/engines/comfy/comfy_gallery_client.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';
import 'package:sd_companion/ui/stage/gallery_viewer.dart';

/// One entry, from whichever addon answered.
class _Entry {
  final String key;
  final Uri thumb;

  /// Full resolution, fetched only when the viewer opens - the grid never
  /// touches it.
  final Uri full;
  final String caption;
  final GeneratedImage Function() promote;

  const _Entry({
    required this.key,
    required this.thumb,
    required this.full,
    required this.caption,
    required this.promote,
  });
}

class GalleryPage extends StatefulWidget {
  final EngineEndpoint endpoint;

  const GalleryPage({super.key, required this.endpoint});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final _modern = ApertureGalleryClient();
  final _legacy = ComfyGalleryClient();
  final _scroll = ScrollController();
  final _search = TextEditingController();

  /// Owned by the State, so the day strip keeps its position when the grid
  /// below it reloads. Rebuilding the strip from scratch on every filter
  /// change is what sent it back to the first chip.
  final _dayScroll = ScrollController();

  final List<_Entry> _entries = [];
  final Set<String> _selected = {};
  List<ApertureGalleryDay> _days = const [];
  ApertureGalleryDay? _day;

  bool _useModern = true;

  /// First load only. A filter change uses [_switching] instead, which keeps
  /// the existing grid on screen - blanking to a spinner for every date tap
  /// is what made the screen flicker.
  bool _loading = true;
  bool _switching = false;
  bool _loadingMore = false;
  int? _nextOffset;
  int _total = 0;
  String? _error;
  String _query = '';

  static const _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _start();
  }

  @override
  void dispose() {
    _dayScroll.dispose();
    _scroll.dispose();
    _search.dispose();
    _modern.dispose();
    _legacy.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_useModern || _loadingMore || _nextOffset == null) return;
    // Fetch the next page before the user reaches the bottom, so scrolling
    // stays continuous rather than stalling at each page boundary.
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _start({bool refresh = false}) async {
    if (refresh) ApertureGalleryClient.clearCache(widget.endpoint);

    final available = await _modern.isAvailable(widget.endpoint);
    if (!mounted) return;
    _useModern = available;

    // With a cached first page there is something to draw immediately, so
    // the spinner is skipped entirely and the screen opens instantly.
    final warm = !refresh &&
        available &&
        _modern.hasCachedFirstPage(widget.endpoint);

    setState(() {
      _loading = !warm;
      _error = null;
      _entries.clear();
      _selected.clear();
      _nextOffset = null;
    });

    if (!available) {
      await _loadLegacy(refresh: refresh);
      return;
    }

    try {
      _days = await _modern.days(widget.endpoint, refresh: refresh);
    } catch (_) {
      _days = const [];
    }
    if (!mounted) return;

    await _loadPage(reset: true, refresh: refresh);
    if (!mounted || refresh || !warm) return;

    // Opened from cache: the only thing it can be missing is images made
    // since, and those are newest-first - so re-asking for page one is
    // enough to catch up, and costs one small request rather than a reload.
    await _refreshNewest();
  }

  /// Re-fetches page one past the cache, and folds in anything new.
  Future<void> _refreshNewest() async {
    try {
      final bounds = _day?.bounds;
      final fresh = await _modern.list(
        widget.endpoint,
        offset: 0,
        limit: _pageSize,
        since: bounds?.$1,
        until: bounds?.$2,
        query: _query,
        refresh: true,
      );
      if (!mounted) return;
      final known = _entries.map((e) => e.key).toSet();
      final added = fresh.items
          .map(_fromModern)
          .where((e) => !known.contains(e.key))
          .toList();
      if (added.isEmpty) {
        setState(() => _total = fresh.total);
        return;
      }
      setState(() {
        _entries.insertAll(0, added);
        _total = fresh.total;
      });
    } catch (_) {
      // A failed background refresh leaves the cached view in place, which
      // is strictly better than replacing it with an error.
    }
  }

  Future<void> _loadPage({bool reset = false, bool refresh = false}) async {
    try {
      final bounds = _day?.bounds;
      final page = await _modern.list(
        widget.endpoint,
        offset: reset ? 0 : (_nextOffset ?? 0),
        limit: _pageSize,
        since: bounds?.$1,
        until: bounds?.$2,
        query: _query,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(page.items.map(_fromModern));
        _total = page.total;
        _nextOffset = page.nextOffset;
        _loading = false;
        _loadingMore = false;
        _switching = false;
      });
      // A new filter starts at the top; keeping the old scroll offset would
      // land mid-way through an unrelated set of images.
      if (reset && _scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _switching = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    await _loadPage();
  }

  /// The old addon has no paging, so everything arrives at once and the
  /// filtering happens here. Kept working, deliberately not optimised - the
  /// answer to a slow gallery is the new addon, not more client cleverness.
  Future<void> _loadLegacy({bool refresh = false}) async {
    try {
      final all = await _legacy.fetchAll(widget.endpoint, forceRefresh: refresh);
      if (!mounted) return;
      final needle = _query.toLowerCase();
      final filtered = needle.isEmpty
          ? all
          : all.where((i) => i.filename.toLowerCase().contains(needle)).toList();
      setState(() {
        _entries
          ..clear()
          ..addAll(filtered.map(_fromLegacy));
        _total = filtered.length;
        _nextOffset = null;
        _loading = false;
        _switching = false;
      });
    } on ComfyGalleryUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '${e.message}\n\nInstall the bundled aperture_gallery addon '
            '(see comfy_addon/ in the app repo) for a much faster gallery.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  _Entry _fromModern(ApertureGalleryItem item) => _Entry(
        key: item.path,
        thumb: item.thumbUri(widget.endpoint, width: 256),
        full: item.fullUri(widget.endpoint),
        caption: item.path,
        promote: () => item.toGeneratedImage(widget.endpoint),
      );

  _Entry _fromLegacy(ComfyGalleryImage item) => _Entry(
        key: item.url,
        // No thumbnail endpoint on the old addon, so this is the full image
        // shrunk on the phone - which is exactly the cost the new one avoids.
        thumb: item.viewUri(widget.endpoint),
        full: item.viewUri(widget.endpoint),
        caption: item.filename,
        promote: () => item.toGeneratedImage(widget.endpoint),
      );

  void _applyFilters() {
    setState(() => _switching = true);
    if (_useModern) {
      _loadPage(reset: true);
    } else {
      _loadLegacy();
    }
  }

  void _send() {
    final chosen = _entries
        .where((e) => _selected.contains(e.key))
        .map((e) => e.promote())
        .toList();
    Navigator.of(context).pop<List<GeneratedImage>>(chosen.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Desk(
      mode: brightness == Brightness.dark ? DeskMode.night : DeskMode.day,
      child: Builder(
        builder: (context) {
          final p = DeskTheme.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  DeskPageHeader(
                    title: 'Server gallery',
                    onClose: () => Navigator.of(context).pop(),
                    action: _selected.isEmpty
                        ? DeskButton(
                            label: 'Refresh',
                            icon: Icons.refresh_rounded,
                            onPressed:
                                _loading ? null : () => _start(refresh: true),
                          )
                        : DeskButton(
                            label: 'Add ${_selected.length}',
                            icon: Icons.check_rounded,
                            kind: DeskButtonKind.primary,
                            onPressed: _send,
                          ),
                  ),
                  Expanded(child: _body(p)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(DeskPalette p) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Space.xxl),
          child: DeskProgress(caption: 'READING THE SERVER LIBRARY'),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 30, color: DeskPalette.alert),
              const SizedBox(height: Space.md),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: Type.body.copyWith(color: p.inkMuted)),
              const SizedBox(height: Space.lg),
              DeskButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: () => _start(refresh: true),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.sm, Space.gutter, Space.sm),
          child: DeskField(
            label: _total > 0 ? 'Search · $_total images' : 'Search',
            controller: _search,
            hint: 'Filename',
            onChanged: (v) {
              _query = v.trim();
              _applyFilters();
            },
          ),
        ),
        if (_useModern && _days.isNotEmpty) _dayStrip(p),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.fade,
            switchInCurve: Motion.ease,
            switchOutCurve: Motion.ease,
            // Keyed on the filter, so a date change cross-fades between two
            // grids instead of tearing one down and building another.
            child: KeyedSubtree(
              key: ValueKey('${_day?.day ?? 'all'}|$_query|${_entries.length}'),
              child: AnimatedOpacity(
                duration: Motion.fade,
                opacity: _switching ? 0.35 : 1,
                child: _grid(p),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Days come from their own endpoint, so this costs one tiny request
  /// rather than requiring the whole library up front.
  Widget _dayStrip(DeskPalette p) => SizedBox(
        height: 52,
        child: ListView(
          controller: _dayScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          children: [
            _dayChip(p, label: 'All', count: null, selected: _day == null,
                onTap: () {
              setState(() => _day = null);
              _applyFilters();
            }),
            for (final day in _days)
              _dayChip(
                p,
                label: day.day,
                count: day.count,
                selected: _day?.day == day.day,
                onTap: () {
                  setState(() => _day = day);
                  _applyFilters();
                },
              ),
          ],
        ),
      );

  Widget _dayChip(
    DeskPalette p, {
    required String label,
    required int? count,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: Space.sm),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            margin: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
              color: selected ? p.clay : p.paper,
              borderRadius: BorderRadius.circular(Corner.control),
              border: Border.all(color: p.ink, width: Stroke.standard),
              boxShadow: Elevation.rest.shadows(p.ink),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: Type.label
                        .copyWith(color: selected ? p.paper : p.ink, fontSize: 11)),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text('$count',
                      style: Type.micro.copyWith(
                          color: selected ? p.paper : p.inkFaint)),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _grid(DeskPalette p) {
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty && _day == null
              ? 'This server has no output images yet.'
              : 'Nothing matches those filters.',
          style: Type.body.copyWith(color: p.inkFaint),
        ),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 120).floor().clamp(3, 6);
    // Even with server thumbnails, decoding at cell size rather than at the
    // JPEG's own size keeps the image cache small enough to scroll freely.
    final decodeWidth = (width / columns * dpr).round();

    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, 0, Space.gutter, Space.xl),
      // Only a screenful either side stays decoded; the default holds far too
      // many bitmaps over a library this size.
      cacheExtent: 600,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: Space.xs,
        crossAxisSpacing: Space.xs,
      ),
      itemCount: _entries.length + (_loadingMore ? columns : 0),
      itemBuilder: (context, i) {
        if (i >= _entries.length) {
          return Container(color: p.paperEdge);
        }
        return _tile(p, _entries[i], i, decodeWidth);
      },
    );
  }

  void _toggle(String key) => setState(() {
        if (!_selected.remove(key)) _selected.add(key);
      });

  Future<void> _openViewer(int index) async {
    await Navigator.of(context).push(
      DeskPageRoute<void>(
        builder: (_) => GalleryViewer(
          entries: [
            for (final entry in _entries)
              ViewerEntry(
                key: entry.key,
                full: entry.full,
                thumb: entry.thumb,
                caption: entry.caption,
              ),
          ],
          initialIndex: index,
          selected: _selected,
          onToggle: _toggle,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _tile(DeskPalette p, _Entry entry, int index, int decodeWidth) {
    final selected = _selected.contains(entry.key);
    final selecting = _selected.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // While a selection is in progress, tapping continues it rather than
      // dropping the user into a viewer - the standard gallery convention,
      // and the only one that makes picking twenty images bearable.
      onTap: () => selecting ? _toggle(entry.key) : _openViewer(index),
      onLongPress: () => _toggle(entry.key),
      child: Container(
        decoration: BoxDecoration(
          color: p.paperEdge,
          border: Border.all(
            color: selected ? p.clay : p.ink,
            width: selected ? Stroke.live : Stroke.hairline,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              entry.thumb.toString(),
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
              errorBuilder: (context, _, __) =>
                  Icon(Icons.broken_image_outlined, size: 16, color: p.inkFaint),
            ),
            if (selected)
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(2),
                  decoration:
                      BoxDecoration(color: p.clay, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 12, color: p.paper),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
