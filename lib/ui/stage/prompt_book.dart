// ==================== Prompt Book ==================== //
//
// CHECKLIST 6.1 and 6.2: everything the app already remembers about what you
// have typed.
//
// `PromptBookStore` has held all of this since the rebuild - a 300-entry
// history that self-persists, a favourites set, and fragments ranked by how
// often each phrase appears across that history. None of it had a screen, so
// none of it existed as far as anyone using the app was concerned.
//
// Two things here exist purely for speed, because 300 paragraph-long prompts
// found both of them immediately:
//
//  * the list is **lazy and fixed-extent**, rather than a Column of every
//    entry inside the drawer's scroll view;
//  * `PromptBookState.fragments` is **memoised**, because it walks the whole
//    history and sorts, and calling it from `build` re-ranked everything on
//    every keystroke.

import 'package:flutter/material.dart';

import 'package:sd_companion/state/prompt_book_store.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

enum PromptBookTab { history, favourites, fragments }

class PromptBookBody extends StatefulWidget {
  final PromptBookStore store;

  /// Replaces the prompt outright - picking a past prompt means "use this".
  final ValueChanged<String> onUse;

  /// Appends a fragment to what is already typed, because a fragment is a
  /// building block rather than a whole prompt.
  final ValueChanged<String> onAppend;

  const PromptBookBody({
    super.key,
    required this.store,
    required this.onUse,
    required this.onAppend,
  });

  @override
  State<PromptBookBody> createState() => _PromptBookBodyState();
}

class _PromptBookBodyState extends State<PromptBookBody> {
  PromptBookTab _tab = PromptBookTab.history;
  final _filter = TextEditingController();
  String _query = '';

  /// Cache for the ranked fragments, keyed on the state object itself. The
  /// state is immutable, so the ranking can only change when the object
  /// does - and recomputing it per build meant sorting every phrase in the
  /// history each time a star was tapped.
  PromptBookState? _fragmentsFor;
  List<PromptFragment> _fragments = const [];

  List<PromptFragment> _rankedFragments(PromptBookState book) {
    if (identical(_fragmentsFor, book)) return _fragments;
    _fragmentsFor = book;
    _fragments = book.fragments;
    return _fragments;
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<String> _visible(List<String> prompts) {
    if (_query.isEmpty) return prompts;
    final needle = _query.toLowerCase();
    return prompts.where((p) => p.toLowerCase().contains(needle)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PromptBookState>(
      valueListenable: widget.store,
      builder: (context, book, _) {
        final p = DeskTheme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DeskTabStrip<PromptBookTab>(
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
              tabs: const [
                DeskTab(
                    value: PromptBookTab.history,
                    label: 'Recent',
                    icon: Icons.history_rounded),
                DeskTab(
                    value: PromptBookTab.favourites,
                    label: 'Saved',
                    icon: Icons.star_rounded),
                DeskTab(
                    value: PromptBookTab.fragments,
                    label: 'Phrases',
                    icon: Icons.auto_awesome_motion_rounded),
              ],
            ),
            Container(height: Stroke.standard, color: p.ink),
            const SizedBox(height: Space.md),
            if (_tab != PromptBookTab.fragments) ...[
              DeskField(
                label: 'Filter',
                controller: _filter,
                hint: 'Search your prompts',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: Space.md),
            ],
            switch (_tab) {
              PromptBookTab.history => _list(
                  context,
                  _visible(book.history),
                  book,
                  emptyMessage: _query.isEmpty
                      ? 'Prompts you generate with show up here automatically.'
                      : 'Nothing matches that search.',
                ),
              PromptBookTab.favourites => _list(
                  context,
                  _visible(book.favourites.toList()),
                  book,
                  emptyMessage: _query.isEmpty
                      ? 'Star a prompt to keep it here, past the 300-entry cap.'
                      : 'No saved prompt matches that search.',
                ),
              PromptBookTab.fragments => _fragmentList(context, book),
            },
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context, String message) {
    final p = DeskTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxl),
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: Type.body.copyWith(color: p.inkFaint)),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<String> prompts,
    PromptBookState book, {
    required String emptyMessage,
  }) {
    if (prompts.isEmpty) return _empty(context, emptyMessage);
    final p = DeskTheme.of(context);

    // Bounded height plus a builder, so only the rows on screen are ever laid
    // out. Building all 300 eagerly inside the drawer's own scroll view is
    // what made this crawl, and long prompts made every row expensive - the
    // two costs multiplied.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.45;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: prompts.length,
        // A fixed extent is what keeps the list lazy: without it Flutter has
        // to measure every child to know the scroll extent, which defeats
        // the point.
        itemExtent: 64,
        itemBuilder: (context, i) {
          final prompt = prompts[i];
          final favourite = book.favourites.contains(prompt);
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: p.ink.withValues(alpha: 0.15),
                    width: Stroke.hairline),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onUse(prompt);
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        prompt,
                        style: Type.body.copyWith(color: p.ink),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                _iconButton(
                  icon:
                      favourite ? Icons.star_rounded : Icons.star_border_rounded,
                  colour: favourite ? p.clay : p.inkFaint,
                  onTap: () => widget.store.toggleFavourite(prompt),
                ),
                _iconButton(
                  icon: Icons.close_rounded,
                  colour: p.inkFaint,
                  onTap: () => widget.store.forget(prompt),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _fragmentList(BuildContext context, PromptBookState book) {
    final fragments = _rankedFragments(book);
    if (fragments.isEmpty) {
      return _empty(
        context,
        'Phrases you reuse across prompts collect here, most-used first.',
      );
    }
    final p = DeskTheme.of(context);
    // Only the top slice is worth showing. A long tail of single-use phrases
    // is noise, and rendering hundreds of chips is the same trap as the list.
    final shown = fragments.length > 60 ? fragments.sublist(0, 60) : fragments;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final fragment in shown)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onAppend(fragment.text),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.sm),
              decoration: BoxDecoration(
                color: p.paper,
                borderRadius: BorderRadius.circular(Corner.control),
                border: Border.all(color: p.ink, width: Stroke.standard),
                boxShadow: Elevation.rest.shadows(p.ink),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(fragment.text,
                        style: Type.label.copyWith(color: p.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: Space.sm),
                  Text('${fragment.uses}',
                      style: Type.micro.copyWith(color: p.inkFaint)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color colour,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: Space.touch,
          height: Space.touch,
          child: Icon(icon, size: 18, color: colour),
        ),
      );
}
