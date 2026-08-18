// ==================== State Inspector ==================== //

import 'package:flutter/material.dart';

import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/state/engine_store.dart';
import 'package:sd_companion/state/library_store.dart';
import 'package:sd_companion/state/prompt_book_store.dart';
import 'package:sd_companion/state/run_store.dart';
import 'package:sd_companion/state/session_store.dart';
import 'package:sd_companion/ui/glass/glass_tokens.dart';
import 'package:sd_companion/ui/glass/liquid_glass.dart';

/// Live view of every store, with controls that mutate them.
///
/// This is the on-device proof that the framework is wired correctly: press
/// a control, and the readouts above it must update with no `setState`
/// anywhere in this file beyond the builders themselves. If a value does not
/// move, the store is not observable - which is precisely the failure mode
/// the old mutable globals had.
class StateInspector extends StatelessWidget {
  const StateInspector({super.key});

  @override
  Widget build(BuildContext context) {
    final rt = RuntimeScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // ===== Engine ===== //
        _Panel(
          title: 'EngineStore',
          child: ValueListenableBuilder<EngineState>(
            valueListenable: rt.engine,
            builder: (context, s, _) => Column(
              children: [
                _Row('active', s.active.label),
                _Row('endpoint', s.endpoint.display),
                _Row('status', s.status.label),
                _Row('capabilities.workflows', '${s.capabilities.workflows}'),
                _Row('capabilities.loras', '${s.capabilities.loras}'),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: _Button(
                        label: 'Forge',
                        active: s.active == EngineKind.forge,
                        tint: Palette.ember,
                        onTap: () => rt.engine.setActive(EngineKind.forge),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Button(
                        label: 'Comfy',
                        active: s.active == EngineKind.comfy,
                        tint: Palette.iris,
                        onTap: () => rt.engine.setActive(EngineKind.comfy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: _Button(
                        label: 'Connect',
                        onTap: rt.engine.markConnected,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Button(
                        label: 'Drop',
                        onTap: () => rt.engine.markUnreachable('Dev test'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ===== Session ===== //
        _Panel(
          title: 'SessionStore',
          child: ValueListenableBuilder<SessionState>(
            valueListenable: rt.session,
            builder: (context, s, _) => Column(
              children: [
                _Row('mode', s.mode.label),
                _Row('prompt', s.prompt.isEmpty ? '—' : s.prompt),
                _Row('steps', '${s.sampling.steps}'),
                _Row('cfg', s.sampling.cfgScale.toStringAsFixed(2)),
                _Row('size', '${s.sampling.width}x${s.sampling.height}'),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: _Button(
                        label: 'Type prompt',
                        onTap: () => rt.session
                            .setPrompt('golden hour, rain-slick street'),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Button(
                        label: 'Clear',
                        onTap: rt.session.clearPrompt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: _Button(
                        label: 'Steps +4',
                        onTap: () => rt.session.tuneSampling(
                          (p) => p.copyWith(steps: p.steps + 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Button(
                        label: 'CFG +0.5',
                        onTap: () => rt.session.tuneSampling(
                          (p) => p.copyWith(cfgScale: p.cfgScale + 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ===== Run ===== //
        _Panel(
          title: 'RunStore',
          child: ValueListenableBuilder<RunState>(
            valueListenable: rt.run,
            builder: (context, s, _) => Column(
              children: [
                _Row('phase', s.phase.label),
                _Row('percent', s.progress.percent == null ? '—' : '${s.progress.percent}%'),
                _Row('active', '${s.isActive}'),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: _Button(
                        label: 'Start',
                        onTap: () async =>
                            rt.run.begin(await rt.session.toSpec()),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Button(
                        label: '+25%',
                        onTap: () {
                          final next = ((s.progress.fraction ?? 0) + 0.25).clamp(0.0, 1.0);
                          rt.run.report(RunProgress(
                            phase: RunPhase.running,
                            fraction: next,
                          ));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(child: _Button(label: 'Done', onTap: rt.run.succeed)),
                    const SizedBox(width: Space.sm),
                    Expanded(child: _Button(label: 'Reset', onTap: rt.run.reset)),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ===== Library ===== //
        _Panel(
          title: 'LibraryStore',
          child: ValueListenableBuilder<LibraryState>(
            valueListenable: rt.library,
            builder: (context, s, _) => Column(
              children: [
                _Row('count', '${s.count}'),
                _Row('selected', s.selected?.id.split('_').last ?? '—'),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: _Button(
                        label: 'Add image',
                        onTap: () => rt.library.add([
                          GeneratedImage.fromRun(
                            url: 'https://example.invalid/${DateTime.now().millisecondsSinceEpoch}.png',
                            engine: rt.engine.active,
                            prompt: rt.session.state.prompt,
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _Button(
                        label: 'Remove',
                        onTap: () {
                          final id = rt.library.selected?.id;
                          if (id != null) rt.library.remove(id);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ===== Prompt book ===== //
        _Panel(
          title: 'PromptBookStore',
          child: ValueListenableBuilder<PromptBookState>(
            valueListenable: rt.promptBook,
            builder: (context, s, _) => Column(
              children: [
                _Row('history', '${s.history.length}'),
                _Row('favourites', '${s.favourites.length}'),
                _Row('fragments', '${s.fragments.length}'),
                if (s.fragments.isNotEmpty)
                  _Row('top fragment',
                      '${s.fragments.first.text} (${s.fragments.first.uses})'),
                const SizedBox(height: Space.md),
                _Button(
                  label: 'Record current prompt',
                  onTap: () => rt.promptBook.record(rt.session.state.prompt),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: GlassSurface(
        weight: GlassWeight.lens,
        radius: Radii.pane,
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: Type.micro),
            const SizedBox(height: Space.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: Type.body.copyWith(fontSize: 12.5, color: Palette.chalk40)),
          ),
          Expanded(
            child: Text(
              value,
              style: Type.readout,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? tint;

  const _Button({
    required this.label,
    required this.onTap,
    this.active = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? Palette.chalk;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        // 44pt minimum touch target, per the design rules.
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.22) : Palette.chalk08,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.6) : Palette.chalk15,
            ),
          ),
          child: Text(
            label,
            style: Type.label.copyWith(
              color: active ? accent : Palette.chalk70,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
