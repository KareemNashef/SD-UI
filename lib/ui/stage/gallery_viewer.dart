// ==================== Gallery Viewer ==================== //
//
// Full-resolution view of one server image, swipeable across the whole
// loaded set and zoomable.
//
// Thumbnails are what the grid shows; this is where the full `/view` image is
// finally worth fetching, and only for the one being looked at. Each page
// keeps its own zoom, so swiping away and back does not silently reset a
// close inspection.

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// One viewable image: what to show, and how to identify it for selection.
class ViewerEntry {
  final String key;
  final Uri full;
  final Uri thumb;
  final String caption;

  const ViewerEntry({
    required this.key,
    required this.full,
    required this.thumb,
    required this.caption,
  });
}

class GalleryViewer extends StatefulWidget {
  final List<ViewerEntry> entries;
  final int initialIndex;
  final Set<String> selected;

  /// Toggles selection; the viewer keeps its own copy so the tick updates
  /// without waiting for the grid behind it to rebuild.
  final ValueChanged<String> onToggle;

  const GalleryViewer({
    super.key,
    required this.entries,
    required this.initialIndex,
    required this.selected,
    required this.onToggle,
  });

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late final Set<String> _selected = {...widget.selected};

  /// One transform per page. Sharing a single controller would carry one
  /// image's zoom onto the next, which is disorienting when swiping.
  final Map<int, TransformationController> _transforms = {};

  @override
  void dispose() {
    for (final controller in _transforms.values) {
      controller.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  TransformationController _transformFor(int index) =>
      _transforms.putIfAbsent(index, TransformationController.new);

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Desk(
      mode: brightness == Brightness.dark ? DeskMode.night : DeskMode.day,
      child: Builder(
        builder: (context) {
          final p = DeskTheme.of(context);
          final entry = widget.entries[_index];
          final selected = _selected.contains(entry.key);

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  DeskPageHeader(
                    title: '${_index + 1} of ${widget.entries.length}',
                    onClose: () => Navigator.of(context).pop(),
                    action: DeskButton(
                      label: selected ? 'Selected' : 'Select',
                      icon: selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      kind: selected
                          ? DeskButtonKind.primary
                          : DeskButtonKind.secondary,
                      onPressed: () {
                        widget.onToggle(entry.key);
                        setState(() {
                          if (!_selected.remove(entry.key)) {
                            _selected.add(entry.key);
                          }
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: widget.entries.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) {
                        final item = widget.entries[i];
                        return InteractiveViewer(
                          transformationController: _transformFor(i),
                          minScale: 1,
                          maxScale: 8,
                          child: Center(
                            child: Image.network(
                              item.full.toString(),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              // The thumbnail is already cached from the
                              // grid, so it appears at once and is replaced
                              // when the full image arrives - rather than
                              // showing an empty frame during the download.
                              frameBuilder:
                                  (context, child, frame, wasSynchronous) {
                                if (frame != null || wasSynchronous) {
                                  return child;
                                }
                                return Image.network(
                                  item.thumb.toString(),
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                );
                              },
                              errorBuilder: (context, _, __) => Icon(
                                Icons.broken_image_outlined,
                                size: 32,
                                color: p.inkFaint,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Space.gutter, Space.sm, Space.gutter, Space.md),
                    child: Text(
                      entry.caption,
                      textAlign: TextAlign.center,
                      style: Type.micro.copyWith(color: p.inkFaint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
