// ==================== Model Browser ==================== //
//
// Picking a checkpoint or a LoRA, from thumbnails instead of filenames.
//
// The list this replaces was ComfyUI's own combo: forty strings that read
// `krea\SummerVibesHM_krea2_epoch8.safetensors`, in a dropdown, on a phone.
// Choosing between two of them meant remembering which was which.
//
// The organising rule is that **the node's combo options are the spine of
// this page, not the addon's library**. Every row starts as one option the
// node will actually accept and is then enriched with whatever the
// ComfyUI-Lora-Manager addon knows about it. So:
//
//   * a model the addon has never heard of still appears, as a plain card,
//     and is still pickable - the browser never becomes a way to lose
//     access to a file;
//   * a model the addon knows about but this node cannot load never
//     appears, because picking it would write a graph that fails at run
//     time;
//   * with no addon installed at all the page degrades to a searchable
//     list of names, which is still better than the dropdown was.
//
// Video previews (`.mp4`) cannot be decoded here. Rather than show a dead
// tile, the card quietly asks the addon for that model's cached Civitai
// stills and uses the first one as a poster; failing that it falls back to
// a marked placeholder.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sd_companion/data/engines/comfy/lora_manager_client.dart';
import 'package:sd_companion/data/engines/comfy/model_library.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// What the browser hands back: the exact combo option to write into the
/// graph, plus whatever was known about it (for a confirmation message).
class ModelPick {
  final String option;
  final ManagedModel? model;
  const ModelPick(this.option, this.model);

  String get label => model?.name ?? option;
}

/// One row of the browser: a combo option the node accepts, and the addon's
/// record for it when there is one.
class BrowsableModel {
  final String option;
  final ManagedModel? model;
  const BrowsableModel(this.option, this.model);

  String get displayName => model?.name ?? _tail(option);
  String get fileLabel => model?.basename ?? _tail(option);
  String get folder => model?.folder ?? _folderOf(option);
  String get baseModel => model?.baseModel ?? '';
  List<String> get tags => model?.tags ?? const [];

  static String _tail(String option) {
    final normalised = option.replaceAll('\\', '/');
    return normalised.contains('/') ? normalised.split('/').last : normalised;
  }

  static String _folderOf(String option) {
    final normalised = option.replaceAll('\\', '/');
    final cut = normalised.lastIndexOf('/');
    return cut <= 0 ? '' : normalised.substring(0, cut);
  }

  bool matches(String needle) {
    if (needle.isEmpty) return true;
    if (displayName.toLowerCase().contains(needle)) return true;
    if (option.toLowerCase().contains(needle)) return true;
    return tags.any((tag) => tag.toLowerCase().contains(needle));
  }
}

/// Pairs the node's combo [options] with the addon's [models].
///
/// Matching is on the path relative to the model root, case-folded and
/// forward-slashed, because ComfyUI reports `krea\file.safetensors` on
/// Windows while the addon reports folder `krea` and an absolute path. The
/// bare file name is the fallback: the addon's folder is relative to *its*
/// root, which is not always the same root the node enumerates.
List<BrowsableModel> pairOptionsWithModels(
  List<String> options,
  List<ManagedModel> models,
) {
  final byKey = <String, ManagedModel>{};
  final byName = <String, ManagedModel>{};
  for (final model in models) {
    byKey[model.comfyKey] = model;
    byName.putIfAbsent(model.basename.toLowerCase(), () => model);
  }
  return [
    for (final option in options)
      BrowsableModel(
        option,
        byKey[option.replaceAll('\\', '/').toLowerCase()] ??
            byName[BrowsableModel._tail(option).toLowerCase()],
      ),
  ];
}

class ModelBrowserPage extends StatefulWidget {
  final ModelLibrary library;
  final ManagedModelKind kind;

  /// The node's own combo options - the only values it will accept.
  final List<String> options;

  /// Whichever option is currently set, marked in the grid.
  final String? current;

  const ModelBrowserPage({
    super.key,
    required this.library,
    required this.kind,
    required this.options,
    this.current,
  });

  @override
  State<ModelBrowserPage> createState() => _ModelBrowserPageState();
}

class _ModelBrowserPageState extends State<ModelBrowserPage> {
  final _searchField = TextEditingController();

  List<BrowsableModel> _entries = const [];
  bool _loading = true;

  /// Set when the addon is missing. Not an error state - the page still
  /// works, it just has nothing but names to show.
  bool _bare = false;

  String _search = '';
  String? _folder;
  String? _baseModel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await widget.library.ensureLoaded(widget.kind);
    if (!mounted) return;
    final models = widget.library.modelsFor(widget.kind);
    setState(() {
      _entries = pairOptionsWithModels(widget.options, models);
      _bare = models.isEmpty;
      _loading = false;
    });
  }

  List<BrowsableModel> get _visible {
    final needle = _search.toLowerCase();
    return _entries.where((entry) {
      if (_folder != null && entry.folder != _folder) return false;
      if (_baseModel != null && entry.baseModel != _baseModel) return false;
      return entry.matches(needle);
    }).toList();
  }

  List<String> get _folders {
    final found = {
      for (final entry in _entries)
        if (entry.folder.isNotEmpty) entry.folder,
    }.toList()
      ..sort();
    return found;
  }

  List<String> get _baseModels {
    final found = {
      for (final entry in _entries)
        if (entry.baseModel.isNotEmpty) entry.baseModel,
    }.toList()
      ..sort();
    return found;
  }

  Future<void> _openDetail(BrowsableModel entry) async {
    final model = entry.model;
    if (model == null) return;
    final detail = await widget.library.detail(widget.kind, model);
    if (!mounted) return;
    // Two navigators are in play: "Use this" has to close the detail drawer
    // *and* return the pick from the page underneath it. Popping the drawer
    // with a flag and acting on it here keeps that in one place - popping
    // the page from inside the drawer's own builder would only ever reach
    // the drawer's route.
    final use = await showDeskDrawer<bool>(
      context: context,
      title: entry.displayName,
      builder: (drawerContext) => _ModelDetailBody(
        entry: entry,
        detail: detail,
        onUse: () => Navigator.of(drawerContext).pop(true),
      ),
    );
    if (use != true || !mounted) return;
    Navigator.of(context).pop(ModelPick(entry.option, entry.model));
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
                    title: widget.kind == ManagedModelKind.lora
                        ? 'LoRAs'
                        : 'Models',
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  _filters(p),
                  Expanded(child: _body(p)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filters(DeskPalette p) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, 0, Space.gutter, Space.sm),
            child: DeskField(
              label: 'Search',
              controller: _searchField,
              hint: 'realism, krea, identity',
              onChanged: (value) => setState(() => _search = value.trim()),
            ),
          ),
          if (_folders.length > 1 || _baseModels.length > 1)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                children: [
                  if (_folders.length > 1) ...[
                    for (final folder in _folders)
                      _chip(p, folder, _folder == folder,
                          () => setState(() => _folder =
                              _folder == folder ? null : folder)),
                  ],
                  if (_folders.length > 1 && _baseModels.length > 1)
                    _divider(p),
                  if (_baseModels.length > 1)
                    for (final base in _baseModels)
                      _chip(p, base, _baseModel == base,
                          () => setState(() => _baseModel =
                              _baseModel == base ? null : base)),
                ],
              ),
            ),
        ],
      );

  Widget _divider(DeskPalette p) => Container(
        width: Stroke.hairline,
        height: 18,
        margin: const EdgeInsets.symmetric(
            horizontal: Space.sm, vertical: Space.md),
        color: p.ink.withValues(alpha: 0.2),
      );

  Widget _chip(DeskPalette p, String label, bool selected, VoidCallback onTap) =>
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
            child: Text(label,
                style: Type.label
                    .copyWith(color: selected ? p.paper : p.ink, fontSize: 11)),
          ),
        ),
      );

  Widget _body(DeskPalette p) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Space.xxl),
          child: DeskProgress(caption: 'READING THE LIBRARY'),
        ),
      );
    }
    if (widget.options.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(
            'This server reports no ${widget.kind.label.toLowerCase()} files.',
            textAlign: TextAlign.center,
            style: Type.body.copyWith(color: p.inkFaint),
          ),
        ),
      );
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Text('Nothing matches that.',
            style: Type.body.copyWith(color: p.inkFaint)),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final columns = (width / 190).floor().clamp(2, 4);
    final decodeWidth = (width / columns * dpr).round();

    return Column(
      children: [
        if (_bare)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, 0, Space.gutter, Space.sm),
            child: Text(
              'Install ComfyUI-Lora-Manager on the server for thumbnails, '
              'tags and descriptions here.',
              style: Type.micro.copyWith(color: p.inkFaint),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, Space.xs, Space.gutter, Space.xl),
            cacheExtent: 800,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Space.md,
              crossAxisSpacing: Space.md,
              childAspectRatio: 0.66,
            ),
            itemCount: visible.length,
            itemBuilder: (context, i) => _card(p, visible[i], decodeWidth),
          ),
        ),
      ],
    );
  }

  Widget _card(DeskPalette p, BrowsableModel entry, int decodeWidth) {
    final selected = entry.option == widget.current;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          Navigator.of(context).pop(ModelPick(entry.option, entry.model)),
      onLongPress: entry.model == null ? null : () => _openDetail(entry),
      child: Container(
        decoration: BoxDecoration(
          color: p.paper,
          border: Border.all(
              color: selected ? p.clay : p.ink,
              width: selected ? Stroke.frame : Stroke.standard),
          boxShadow: (selected ? Elevation.raised : Elevation.rest)
              .shadows(p.ink),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: _preview(p, entry, decodeWidth),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.sm, Space.sm, Space.sm, Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.label.copyWith(color: p.ink, fontSize: 11),
                      ),
                    ),
                    Text(
                      [
                        if (entry.baseModel.isNotEmpty) entry.baseModel,
                        if (entry.model?.sizeLabel.isNotEmpty == true)
                          entry.model!.sizeLabel,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.micro.copyWith(color: p.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(DeskPalette p, BrowsableModel entry, int decodeWidth) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ManagedPreview(
          library: widget.library,
          kind: widget.kind,
          model: entry.model,
          decodeWidth: decodeWidth,
        ),
        if (entry.model?.favorite == true)
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.star_rounded, size: 14, color: p.clay),
            ),
          ),
        if (entry.option == widget.current)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DeskStamp(label: 'IN USE', color: p.clay),
            ),
          ),
        // Details are a long-press, which is not discoverable on its own -
        // this makes the gesture visible without spending a whole row on it.
        if (entry.model != null)
          Align(
            alignment: Alignment.bottomRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openDetail(entry),
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: p.paper,
                  borderRadius: BorderRadius.circular(Corner.photo),
                  border: Border.all(color: p.ink, width: Stroke.hairline),
                ),
                child: Icon(Icons.info_outline_rounded,
                    size: 13, color: p.inkMuted),
              ),
            ),
          ),
      ],
    );
  }

}

/// The thumbnail for one model, wherever it appears.
///
/// A `.mp4` preview cannot be decoded here, so this asks the library for a
/// poster still the first time it is asked to show one and repaints when it
/// arrives. Doing that inside the widget rather than in each screen means
/// the request happens once per model per library, not once per screen.
class ManagedPreview extends StatefulWidget {
  final ModelLibrary library;
  final ManagedModelKind kind;
  final ManagedModel? model;
  final int decodeWidth;

  const ManagedPreview({
    super.key,
    required this.library,
    required this.kind,
    required this.model,
    required this.decodeWidth,
  });

  @override
  State<ManagedPreview> createState() => _ManagedPreviewState();
}

class _ManagedPreviewState extends State<ManagedPreview> {
  bool _asked = false;

  void _requestPoster(ManagedModel model) {
    if (_asked) return;
    _asked = true;
    widget.library.poster(widget.kind, model).then((poster) {
      if (mounted && poster != null) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final model = widget.model;
    Widget content;

    if (model == null || !model.hasPreview) {
      content = _placeholder(p, Icons.help_outline_rounded);
    } else if (model.previewIsVideo) {
      final poster = widget.library.cachedPoster(model);
      if (poster == null && !widget.library.hasDetail(model)) {
        // After the frame, never during it: _asked is set synchronously so
        // a repaint cannot queue the same request twice.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _requestPoster(model);
        });
      }
      content = poster == null
          ? _placeholder(p, Icons.movie_outlined)
          : Image.network(poster,
              fit: BoxFit.cover,
              cacheWidth: widget.decodeWidth,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) =>
                  _placeholder(p, Icons.movie_outlined));
    } else {
      final uri = model.previewUri(widget.library.endpoint);
      content = uri == null
          ? _placeholder(p, Icons.help_outline_rounded)
          : Image.network(uri.toString(),
              fit: BoxFit.cover,
              cacheWidth: widget.decodeWidth,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) =>
                  _placeholder(p, Icons.broken_image_outlined));
    }
    return ColoredBox(color: p.paperEdge, child: content);
  }

  Widget _placeholder(DeskPalette p, IconData icon) => Center(
        child: Icon(icon, size: 20, color: p.inkFaint),
      );
}

/// Everything the addon cached about one model, in a drawer.
class _ModelDetailBody extends StatelessWidget {
  final BrowsableModel entry;
  final ManagedModelDetail detail;
  final VoidCallback onUse;

  const _ModelDetailBody({
    required this.entry,
    required this.detail,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _line(p, 'FILE', entry.fileLabel),
        if (entry.baseModel.isNotEmpty) _line(p, 'BASE MODEL', entry.baseModel),
        if (entry.folder.isNotEmpty) _line(p, 'FOLDER', entry.folder),
        if (entry.model?.sizeLabel.isNotEmpty == true)
          _line(p, 'SIZE', entry.model!.sizeLabel),
        if (detail.creator.isNotEmpty) _line(p, 'BY', detail.creator),
        if (detail.trainedWords.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('TRIGGER WORDS', style: Type.micro.copyWith(color: p.inkFaint)),
          const SizedBox(height: Space.xs),
          // Worth copying rather than retyping: these have to be exact for
          // the LoRA to fire at all.
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: detail.trainedWords.join(', ')));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Trigger words copied')),
              );
            },
            child: Text(detail.trainedWords.join(', '),
                style: Type.body.copyWith(color: p.clay)),
          ),
        ],
        if (entry.tags.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('TAGS', style: Type.micro.copyWith(color: p.inkFaint)),
          const SizedBox(height: Space.xs),
          Text(entry.tags.join(' · '),
              style: Type.body.copyWith(color: p.inkMuted)),
        ],
        if (detail.description.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('ABOUT', style: Type.micro.copyWith(color: p.inkFaint)),
          const SizedBox(height: Space.xs),
          Text(detail.description,
              style: Type.body.copyWith(color: p.inkMuted)),
        ],
        if (detail.examplePrompts.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('EXAMPLE PROMPT', style: Type.micro.copyWith(color: p.inkFaint)),
          const SizedBox(height: Space.xs),
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: detail.examplePrompts.first));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Prompt copied')),
              );
            },
            child: Text(detail.examplePrompts.first,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: Type.body.copyWith(color: p.inkMuted)),
          ),
        ],
        const SizedBox(height: Space.lg),
        DeskButton(
          label: 'Use this',
          icon: Icons.check_rounded,
          kind: DeskButtonKind.primary,
          expand: true,
          onPressed: onUse,
        ),
      ],
    );
  }

  Widget _line(DeskPalette p, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child:
                  Text(label, style: Type.micro.copyWith(color: p.inkFaint)),
            ),
            Expanded(
              child:
                  Text(value, style: Type.body.copyWith(color: p.inkMuted)),
            ),
          ],
        ),
      );
}

/// Opens the browser and returns the chosen combo option, or null.
Future<ModelPick?> pickModel(
  BuildContext context, {
  required ModelLibrary library,
  required ManagedModelKind kind,
  required List<String> options,
  String? current,
}) =>
    Navigator.of(context).push<ModelPick>(
      DeskPageRoute(
        builder: (_) => ModelBrowserPage(
          library: library,
          kind: kind,
          options: options,
          current: current,
        ),
        fullscreenDialog: true,
      ),
    );

/// The one-line stand-in for the browser: what a chosen model looks like
/// where it is set.
///
/// This replaces a `DeskDropdown` full of filenames. The dropdown was not
/// only unreadable, it was also the wrong shape for the job - a list of
/// forty entries in an overlay card is a scroll, not a choice. Here the row
/// shows what is set, with its thumbnail, and opens the full browser to
/// change it.
class ModelPickerTile extends StatefulWidget {
  final ModelLibrary library;
  final ManagedModelKind kind;
  final String label;

  /// The combo option currently written into the graph.
  final String value;

  /// Everything the node will accept.
  final List<String> options;

  final ValueChanged<String> onChanged;

  /// Sits at the right of the row - the LoRA rows put their remove button
  /// here so it stays attached to the thing it removes.
  final Widget? trailing;

  const ModelPickerTile({
    super.key,
    required this.library,
    required this.kind,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.trailing,
  });

  @override
  State<ModelPickerTile> createState() => _ModelPickerTileState();
}

class _ModelPickerTileState extends State<ModelPickerTile> {
  @override
  void initState() {
    super.initState();
    widget.library.ensureLoaded(widget.kind);
  }

  Future<void> _browse() async {
    final pick = await pickModel(
      context,
      library: widget.library,
      kind: widget.kind,
      options: widget.options,
      current: widget.value,
    );
    if (pick == null) return;
    widget.onChanged(pick.option);
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return AnimatedBuilder(
      animation: widget.library.notifierFor(widget.kind),
      builder: (context, _) {
        final model = widget.library.resolve(widget.kind, widget.value);
        final entry = BrowsableModel(widget.value, model);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final subtitle = [
          if (entry.baseModel.isNotEmpty) entry.baseModel,
          entry.fileLabel,
        ].join(' · ');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label.toUpperCase(),
                style: Type.micro.copyWith(color: p.inkFaint)),
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _browse,
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: p.paper,
                        borderRadius: BorderRadius.circular(Corner.control),
                        border: Border.all(color: p.ink, width: Stroke.standard),
                        boxShadow: Elevation.rest.shadows(p.ink),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(
                                  Corner.control - Stroke.standard),
                              bottomLeft: Radius.circular(
                                  Corner.control - Stroke.standard),
                            ),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: ManagedPreview(
                                library: widget.library,
                                kind: widget.kind,
                                model: model,
                                decodeWidth: (56 * dpr).round(),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Space.sm),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Type.label.copyWith(color: p.ink)),
                                  const SizedBox(height: 1),
                                  Text(subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Type.micro
                                          .copyWith(color: p.inkFaint)),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: Space.sm),
                            child: Icon(Icons.grid_view_rounded,
                                size: 15, color: p.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ],
        );
      },
    );
  }
}
