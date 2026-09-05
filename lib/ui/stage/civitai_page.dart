// ==================== Civitai Browser ==================== //
//
// Browse Civitai's public feed and lift the prompt behind an image.
//
// The organising fact is that **only about half of these images carry a
// prompt** - `meta` is present only when the uploader left it in. So the
// grid marks which ones do before you tap, and an image without one says so
// plainly instead of opening an empty panel. Anything else would make the
// screen feel broken for reasons that are nothing to do with this app.
//
// Nothing here writes to the session on its own: "Use prompt" hands the text
// back to the caller, which is what puts it in the prompt field.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sd_companion/data/civitai/civitai_client.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// What the page hands back when the user takes a prompt.
class CivitaiPick {
  final String prompt;
  final String? negativePrompt;
  const CivitaiPick({required this.prompt, this.negativePrompt});
}

class CivitaiPage extends StatefulWidget {
  const CivitaiPage({super.key});

  @override
  State<CivitaiPage> createState() => _CivitaiPageState();
}

class _CivitaiPageState extends State<CivitaiPage> {
  final _client = CivitaiClient();
  final _scroll = ScrollController();

  final List<CivitaiImage> _items = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;

  CivitaiSort _sort = CivitaiSort.reactions;
  CivitaiPeriod _period = CivitaiPeriod.week;
  CivitaiRating _rating = CivitaiRating.safe;

  final _tagField = TextEditingController();
  final _searchField = TextEditingController();

  /// Tag ids sent to the API. Names are impossible here: the public tags
  /// endpoint returns no ids, and the site's autocomplete needs auth - so
  /// `tags` only ever takes the numbers from a civitai.com URL.
  List<int> _tagIds = const [];

  /// Free text matched against the prompt of whatever has been loaded. The
  /// images API has no text search at all, so this is a local filter over
  /// the pages already fetched rather than a query.
  String _search = '';

  /// Only show images that actually carry a prompt. Off by default so the
  /// feed looks like the site, but it is the switch that makes this screen
  /// worth using when you are hunting for prompts specifically.
  bool _promptsOnly = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _tagField.dispose();
    _searchField.dispose();
    _scroll.dispose();
    _client.dispose();
    super.dispose();
  }

  List<CivitaiImage> get _visible {
    final needle = _search.toLowerCase();
    return _items.where((image) {
      if (_promptsOnly && !image.hasPrompt) return false;
      if (needle.isEmpty) return true;
      return (image.prompt ?? '').toLowerCase().contains(needle);
    }).toList();
  }

  void _onScroll() {
    if (_loading || _loadingMore || _exhausted) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 900) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
        _items.clear();
        _cursor = null;
        _exhausted = false;
      } else {
        _loadingMore = true;
      }
    });

    try {
      final page = await _client.images(
        cursor: reset ? null : _cursor,
        rating: _rating,
        sort: _sort,
        period: _period,
        tagIds: _tagIds,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _exhausted = !page.hasMore || page.items.isEmpty;
        _loading = false;
        _loadingMore = false;
      });
      if (reset && _scroll.hasClients) _scroll.jumpTo(0);

      // A whole page can be filtered away locally, leaving the grid looking
      // stuck on an empty screen. Keep pulling until something shows.
      final filtering = _promptsOnly || _search.isNotEmpty;
      if (filtering && !_exhausted && _visible.length < 12 && mounted) {
        await _load();
      }
    } on CivitaiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openDetail(CivitaiImage image) async {
    final pick = await Navigator.of(context).push<CivitaiPick>(
      DeskPageRoute(builder: (_) => _CivitaiDetail(image: image)),
    );
    if (pick != null && mounted) Navigator.of(context).pop(pick);
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
                    title: 'Civitai',
                    onClose: () => Navigator.of(context).pop(),
                    action: DeskButton(
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      onPressed: _loading ? null : () => _load(reset: true),
                    ),
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
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              children: [
                for (final sort in CivitaiSort.values)
                  _chip(p, sort.label, _sort == sort, () {
                    setState(() => _sort = sort);
                    _load(reset: true);
                  }),
                _divider(p),
                for (final period in CivitaiPeriod.values)
                  _chip(p, period.label, _period == period, () {
                    setState(() => _period = period);
                    _load(reset: true);
                  }),
                _divider(p),
                for (final rating in CivitaiRating.values)
                  _chip(p, rating.label, _rating == rating, () {
                    setState(() => _rating = rating);
                    _load(reset: true);
                  }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, 0, Space.gutter, Space.sm),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DeskField(
                        label: 'Search loaded prompts',
                        controller: _searchField,
                        hint: 'castle, golden hour',
                        onChanged: (v) {
                          setState(() => _search = v.trim());
                          // A local filter can empty the grid, so pull more
                          // rather than leaving it looking finished.
                          if (_search.isNotEmpty &&
                              _visible.length < 12 &&
                              !_exhausted &&
                              !_loading) {
                            _load();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      flex: 2,
                      child: DeskField(
                        label: 'Tag ids',
                        controller: _tagField,
                        hint: '5133',
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final ids = v
                              .split(RegExp(r'[^0-9]+'))
                              .where((part) => part.isNotEmpty)
                              .map(int.parse)
                              .toList();
                          if (ids.length == _tagIds.length &&
                              ids.every(_tagIds.contains)) {
                            return;
                          }
                          setState(() => _tagIds = ids);
                          _load(reset: true);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _promptsOnly = !_promptsOnly),
                        child: Text(
                          _tagIds.isNotEmpty
                              ? 'Filtering by tag ${_tagIds.join(', ')}'
                              : (_promptsOnly
                                  ? 'Showing only images that kept their prompt'
                                  : 'Many uploads have no prompt attached'),
                          style: Type.micro.copyWith(color: p.inkFaint),
                        ),
                      ),
                    ),
                    DeskToggle(
                      value: _promptsOnly,
                      onChanged: (v) {
                        setState(() => _promptsOnly = v);
                        if (v && _visible.length < 12 && !_exhausted) _load();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  Widget _divider(DeskPalette p) => Container(
        width: Stroke.hairline,
        height: 20,
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
                style: Type.label.copyWith(
                    color: selected ? p.paper : p.ink, fontSize: 11)),
          ),
        ),
      );

  Widget _body(DeskPalette p) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Space.xxl),
          child: DeskProgress(caption: 'LOADING THE FEED'),
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
                onPressed: () => _load(reset: true),
              ),
            ],
          ),
        ),
      );
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _promptsOnly
              ? 'None of these kept a prompt. Try another sort or period.'
              : 'Nothing came back from Civitai.',
          textAlign: TextAlign.center,
          style: Type.body.copyWith(color: p.inkFaint),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final columns = (width / 150).floor().clamp(2, 5);
    final decodeWidth = (width / columns * dpr).round();

    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, 0, Space.gutter, Space.xl),
      cacheExtent: 700,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: Space.xs,
        crossAxisSpacing: Space.xs,
        childAspectRatio: 0.72,
      ),
      itemCount: visible.length + (_loadingMore ? columns : 0),
      itemBuilder: (context, i) {
        if (i >= visible.length) return ColoredBox(color: p.paperEdge);
        return _tile(p, visible[i], decodeWidth);
      },
    );
  }

  Widget _tile(DeskPalette p, CivitaiImage image, int decodeWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(image),
      child: Container(
        decoration: BoxDecoration(
          color: p.paperEdge,
          border: Border.all(color: p.ink, width: Stroke.hairline),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              image.thumbUrl(width: 450),
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
              errorBuilder: (context, _, __) =>
                  Icon(Icons.broken_image_outlined, size: 16, color: p.inkFaint),
            ),
            // Marking this up front is the difference between a grid you can
            // hunt prompts in and one you tap through at random.
            if (image.hasPrompt)
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.clay,
                    borderRadius: BorderRadius.circular(Corner.photo),
                  ),
                  child: Text('PROMPT',
                      style: Type.micro.copyWith(color: p.paper, fontSize: 7)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One image, full size, with everything the uploader left attached.
class _CivitaiDetail extends StatelessWidget {
  final CivitaiImage image;

  const _CivitaiDetail({required this.image});

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
                    title: image.username == null
                        ? 'Image'
                        : 'by ${image.username}',
                    onClose: () => Navigator.of(context).pop(),
                    action: image.hasPrompt
                        ? DeskButton(
                            label: 'Use prompt',
                            icon: Icons.south_west_rounded,
                            kind: DeskButtonKind.primary,
                            onPressed: () => Navigator.of(context).pop(
                              CivitaiPick(
                                prompt: image.prompt!,
                                negativePrompt: image.negativePrompt,
                              ),
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(Space.gutter),
                      children: [
                        AspectRatio(
                          aspectRatio: image.height == 0
                              ? 1
                              : image.width / image.height,
                          child: Container(
                            decoration: BoxDecoration(
                              color: p.paperEdge,
                              border:
                                  Border.all(color: p.ink, width: Stroke.frame),
                              boxShadow: Elevation.sheet.shadows(p.ink),
                            ),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 6,
                              child: Image.network(
                                image.thumbUrl(width: 1200),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (context, _, __) => Icon(
                                    Icons.broken_image_outlined,
                                    color: p.inkFaint),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.lg),
                        if (image.hasPrompt) ...[
                          _Block(
                            label: 'Prompt',
                            text: image.prompt!,
                            onCopy: () => _copy(context, image.prompt!,
                                'Prompt copied.'),
                          ),
                          if (image.negativePrompt != null) ...[
                            const SizedBox(height: Space.md),
                            _Block(
                              label: 'Negative prompt',
                              text: image.negativePrompt!,
                              onCopy: () => _copy(context,
                                  image.negativePrompt!, 'Negative copied.'),
                            ),
                          ],
                        ] else
                          Container(
                            padding: const EdgeInsets.all(Space.lg),
                            decoration: BoxDecoration(
                              color: p.paperEdge,
                              borderRadius:
                                  BorderRadius.circular(Corner.control),
                              border: Border.all(
                                  color: p.inkFaint, width: Stroke.standard),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 16, color: p.inkFaint),
                                const SizedBox(width: Space.sm),
                                Expanded(
                                  child: Text(
                                    'This uploader did not attach generation '
                                    'data, so there is no prompt to take.',
                                    style:
                                        Type.body.copyWith(color: p.inkFaint),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: Space.lg),
                        _settings(p),
                      ],
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

  Widget _settings(DeskPalette p) {
    final rows = <(String, String)>[
      if (image.baseModel != null) ('Base model', image.baseModel!),
      if (image.model != null) ('Model', image.model!),
      if (image.sampler != null) ('Sampler', image.sampler!),
      if (image.steps != null) ('Steps', '${image.steps}'),
      if (image.cfgScale != null) ('CFG', '${image.cfgScale}'),
      if (image.seed != null) ('Seed', image.seed!),
      ('Size', '${image.width} × ${image.height}'),
      ...image.extra.entries.map((e) => (e.key, e.value)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SETTINGS', style: Type.micro.copyWith(color: p.inkFaint)),
        const SizedBox(height: Space.sm),
        for (final row in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: p.ink.withValues(alpha: 0.15),
                    width: Stroke.hairline),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(row.$1,
                      style: Type.label.copyWith(color: p.inkMuted)),
                ),
                Expanded(
                  child: Text(row.$2,
                      style: Type.readout.copyWith(color: p.ink)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _copy(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _Block extends StatelessWidget {
  final String label;
  final String text;
  final VoidCallback onCopy;

  const _Block({required this.label, required this.text, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label.toUpperCase(),
                  style: Type.micro.copyWith(color: p.inkFaint)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCopy,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: Space.xs),
                child: Icon(Icons.copy_rounded, size: 15, color: p.inkMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: p.paperEdge,
            borderRadius: BorderRadius.circular(Corner.control),
            border: Border.all(color: p.ink, width: Stroke.standard),
          ),
          child: SelectableText(text, style: Type.body.copyWith(color: p.ink)),
        ),
      ],
    );
  }
}
