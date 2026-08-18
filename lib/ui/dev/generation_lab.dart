// ==================== Generation Lab ==================== //

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:sd_companion/data/engines/comfy/comfy_workflow_type.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/runtime/aperture_runtime.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/state/library_store.dart';
import 'package:sd_companion/state/run_store.dart';
import 'package:sd_companion/state/session_store.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// A real generation, driven through the new architecture and dressed in the
/// Desk system.
///
/// This doubles as the first draft of the front page: tool tray on the left,
/// the mounted sheet as the largest object, the print shelf under it, prompt
/// and value chips below, generate always bottom-right. Nothing here touches
/// HTTP and nothing reads a global - the controls write into [SessionStore]
/// and `ApertureRuntime.submit()` does the rest.
class GenerationLab extends StatefulWidget {
  const GenerationLab({super.key});

  @override
  State<GenerationLab> createState() => _GenerationLabState();
}

class _GenerationLabState extends State<GenerationLab> {
  static const _workflowAsset = 'assets/comfy/debug_krea_txt2img.json';

  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '8188');
  final _prompt = TextEditingController(
    text: 'portrait photo of a girl, close up, looking at the camera',
  );

  String _status = 'Not connected';
  bool _busy = false;
  bool _ready = false;
  int _tool = 0;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _prompt.dispose();
    super.dispose();
  }

  ApertureRuntime get _rt => RuntimeScope.read(context);

  EngineEndpoint get _endpoint => EngineEndpoint(
        kind: EngineKind.comfy,
        host: _host.text.trim(),
        port: _port.text.trim(),
      );

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _status = 'Connecting…';
    });

    final endpoint = _endpoint;
    await _rt.engines.invalidate(endpoint);
    _rt.engine.setEndpoint(endpoint);
    _rt.engine.setActive(EngineKind.comfy);

    final reachable = await _rt.engines.of(endpoint).ping();
    if (!mounted) return;
    if (!reachable) {
      _rt.engine.markUnreachable('No answer from ${endpoint.display}');
      setState(() {
        _busy = false;
        _ready = false;
        _status = 'No answer from ${endpoint.display}';
      });
      return;
    }
    _rt.engine.markConnected();

    final workflows = _rt.engines.workflowsFor(endpoint);
    await workflows.loadFor(endpoint);
    try {
      // Re-import every time: the point is to test the bundled graph as
      // shipped, not whatever a previous session left saved and edited.
      final record = await workflows.importWorkflow(
        await rootBundle.loadString(_workflowAsset),
        name: 'Krea txt2img (debug)',
        workflowType: ComfyWorkflowType.textToImage,
      );
      await workflows.selectWorkflow(record.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ready = false;
        _status = 'Workflow import failed: $e';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _ready = workflows.activeDetected.value != null;
      _status = _ready
          ? 'Connected to ${endpoint.display}'
          : workflows.activeError.value ?? 'Workflow could not be analyzed';
    });
  }

  Future<void> _generate() async {
    _rt.session.setPrompt(_prompt.text);
    setState(() => _status = 'Submitting…');
    final result = await _rt.submit();
    if (!mounted) return;
    setState(() {
      _status = result.fold(
        (images) => 'Done — ${images.length} image(s)',
        (error) => error.message,
      );
    });
  }

  Future<void> _openServerDrawer() => showDeskDrawer<void>(
        context: context,
        title: 'Server',
        action: DeskStamp(
          label: _ready ? 'ready' : 'idle',
          color: _ready ? DeskPalette.good : DeskPalette.caution,
        ),
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DeskField(label: 'Host', controller: _host),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: DeskField(
                    label: 'Port',
                    controller: _port,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            DeskButton(
              label: _busy ? 'Working…' : 'Connect & load workflow',
              icon: Icons.link_rounded,
              kind: DeskButtonKind.primary,
              expand: true,
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _connect();
                    },
            ),
          ],
        ),
      );

  Future<void> _openSettingsDrawer() => showDeskDrawer<void>(
        context: context,
        title: 'Generation settings',
        builder: (context) => ValueListenableBuilder<SessionState>(
          valueListenable: _rt.session,
          builder: (context, s, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeskRuler(
                label: 'Steps',
                value: s.sampling.steps.toDouble(),
                min: 1,
                max: 60,
                divisions: 59,
                format: (v) => v.round().toString(),
                onChanged: (v) => _rt.session
                    .tuneSampling((p) => p.copyWith(steps: v.round())),
              ),
              const SizedBox(height: Space.lg),
              DeskRuler(
                label: 'Guidance',
                value: s.sampling.cfgScale,
                min: 1,
                max: 15,
                format: (v) => v.toStringAsFixed(2),
                onChanged: (v) =>
                    _rt.session.tuneSampling((p) => p.copyWith(cfgScale: v)),
              ),
              const SizedBox(height: Space.lg),
              DeskDropdown<int>(
                label: 'Resolution',
                value: s.sampling.width,
                options: const [
                  DeskOption(value: 512, label: '512 × 512'),
                  DeskOption(value: 768, label: '768 × 768', detail: 'DEFAULT'),
                  DeskOption(value: 1024, label: '1024 × 1024'),
                ],
                onChanged: (v) => _rt.session
                    .tuneSampling((p) => p.copyWith(width: v, height: v)),
              ),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Random seed',
                      style:
                          Type.label.copyWith(color: DeskTheme.of(context).ink),
                    ),
                  ),
                  DeskToggle(
                    value: s.sampling.isSeedRandom,
                    onChanged: (random) => _rt.session.tuneSampling(
                      (p) => random
                          ? p.copyWith(clearSeed: true)
                          : p.copyWith(seed: 1104433390),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);

    return Column(
      children: [
        // ===== Title row: what is loaded, and whether it answers ===== //
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.md, Space.gutter, Space.sm),
          child: Row(
            children: [
              DeskCard(label: 'krea txt2img', onTap: _openServerDrawer),
              const SizedBox(width: Space.sm),
              DeskCard(label: 'comfy', accent: true, onTap: _openServerDrawer),
              const Spacer(),
              DeskStamp(
                label: _ready ? 'ready' : 'offline',
                color: _ready ? DeskPalette.good : DeskPalette.caution,
              ),
            ],
          ),
        ),

        // ===== Tray + mounted sheet ===== //
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DeskToolTray(
                  tools: [
                    DeskTool(
                        icon: Icons.dns_rounded,
                        name: 'Server',
                        onTap: _openServerDrawer),
                    DeskTool(
                        icon: Icons.tune_rounded,
                        name: 'Settings',
                        onTap: _openSettingsDrawer),
                    const DeskTool(icon: Icons.brush_rounded, name: 'Mask'),
                    const DeskTool(
                        icon: Icons.photo_library_rounded, name: 'Gallery'),
                  ],
                  activeIndex: _tool,
                  onSelect: (i) => setState(() => _tool = i),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: ValueListenableBuilder<RunState>(
                    valueListenable: _rt.run,
                    builder: (context, run, _) {
                      final preview = run.progress.preview;
                      return MountedSheet(
                        caption: preview != null ? 'PREVIEW' : 'SOURCE',
                        showHandles: preview == null,
                        image: preview != null
                            ? Image.memory(preview,
                                fit: BoxFit.contain, gaplessPlayback: true)
                            : Center(
                                child: Text('NO SOURCE',
                                    style:
                                        Type.micro.copyWith(color: p.inkFaint)),
                              ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: Space.gutter),
              ],
            ),
          ),
        ),

        // ===== Print shelf ===== //
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: ValueListenableBuilder<LibraryState>(
            valueListenable: _rt.library,
            builder: (context, lib, _) {
              if (lib.isEmpty) {
                return SizedBox(
                  height: 110,
                  child: Center(
                    child: Text('NOTHING PRINTED YET',
                        style: Type.micro.copyWith(color: p.inkFaint)),
                  ),
                );
              }
              return PrintShelf(
                stamp: '×${lib.count}',
                selectedId: lib.selectedId,
                onSelect: _rt.library.select,
                entries: [
                  for (final image in lib.images)
                    PrintEntry(id: image.id, image: _preview(image)),
                ],
              );
            },
          ),
        ),

        // ===== Progress, only while a run is in flight ===== //
        ValueListenableBuilder<RunState>(
          valueListenable: _rt.run,
          builder: (context, run, _) => run.isActive
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Space.gutter, Space.sm, Space.gutter, 0),
                  child: DeskProgress(
                    fraction: run.progress.fraction,
                    caption: (run.progress.stage ?? run.progress.phase.label)
                        .toUpperCase(),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ===== Prompt, chips, generate ===== //
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.md, Space.gutter, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeskField(label: 'Prompt', controller: _prompt, maxLines: 2),
              const SizedBox(height: Space.md),
              ValueListenableBuilder<SessionState>(
                valueListenable: _rt.session,
                builder: (context, s, _) => Row(
                  children: [
                    DeskChip(
                      unit: 'steps',
                      value: '${s.sampling.steps}',
                      onTap: _openSettingsDrawer,
                    ),
                    const SizedBox(width: Space.sm),
                    DeskChip(
                      unit: 'cfg',
                      value: s.sampling.cfgScale.toStringAsFixed(1),
                      onTap: _openSettingsDrawer,
                    ),
                    const SizedBox(width: Space.sm),
                    DeskChip(
                      unit: 'size',
                      value: '${s.sampling.width}',
                      onTap: _openSettingsDrawer,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              ValueListenableBuilder<RunState>(
                valueListenable: _rt.run,
                builder: (context, run, _) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        _status,
                        style: Type.micro.copyWith(color: p.inkFaint),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    if (run.isActive)
                      DeskButton(
                        label: 'Stop',
                        kind: DeskButtonKind.destructive,
                        onPressed: _rt.cancelRun,
                      )
                    else
                      DeskButton(
                        label: 'Generate',
                        icon: Icons.play_arrow_rounded,
                        kind: DeskButtonKind.primary,
                        onPressed: _ready ? _generate : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Forge hands back data URLs, ComfyUI hands back `/view` URLs; both end up
  /// on the same shelf, so both have to render here.
  Widget _preview(GeneratedImage image) => image.isDataUrl
      ? Image.memory(
          base64Decode(image.url.substring(image.url.indexOf(',') + 1)),
          fit: BoxFit.cover,
        )
      : Image.network(image.url, fit: BoxFit.cover);
}
