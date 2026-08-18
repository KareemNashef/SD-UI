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
import 'package:sd_companion/state/run_store.dart';
import 'package:sd_companion/state/session_store.dart';
import 'package:sd_companion/ui/glass/glass_controls.dart';
import 'package:sd_companion/ui/glass/glass_tokens.dart';
import 'package:sd_companion/ui/glass/liquid_glass.dart';

/// A real generation, driven entirely through the new architecture.
///
/// This is the end-to-end proof the framework works: the glass controls
/// write into [SessionStore], `ApertureRuntime.submit()` builds a
/// [GenerationSpec] from that store plus the catalogue, the ComfyUI engine
/// runs it, progress arrives on the engine's stream and lands in
/// [RunStore], and the result lands in the library. No widget here touches
/// HTTP, and nothing reads a global.
///
/// The bundled `debug_krea_txt2img.json` workflow supplies the graph, so the
/// only thing needed on the device is a reachable ComfyUI server.
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

  /// Point the runtime at this server, prove it answers, and load the
  /// bundled workflow into its workflow service.
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
      // Re-import every time: the point of this screen is to test against
      // the bundled graph as shipped, not against whatever a previous
      // session left saved and possibly edited.
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
        (images) => 'Done - ${images.length} image(s)',
        (error) => error.message,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        // ===== Server ===== //
        Text('SERVER', style: Type.micro),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: GlassField(label: 'Host', controller: _host),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: GlassField(
                label: 'Port',
                controller: _port,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        GlassButton(
          label: _busy ? 'Working…' : 'Connect & load workflow',
          icon: Icons.hub_rounded,
          tint: Palette.iris,
          filled: true,
          onPressed: _busy ? null : _connect,
        ),
        const SizedBox(height: Space.sm),
        _StatusLine(text: _status, ok: _ready),
        const SizedBox(height: Space.xl),

        // ===== Prompt ===== //
        Text('PROMPT', style: Type.micro),
        const SizedBox(height: Space.md),
        GlassField(label: 'Positive', controller: _prompt, maxLines: 3),
        const SizedBox(height: Space.xl),

        // ===== Sampling, bound to the real session store ===== //
        Text('SAMPLING', style: Type.micro),
        const SizedBox(height: 2),
        Text(
          'These write straight into SessionStore - the numbers below are '
          'read back from it, not from local state.',
          style: Type.body.copyWith(fontSize: 12.5, color: Palette.chalk40),
        ),
        const SizedBox(height: Space.md),
        ValueListenableBuilder<SessionState>(
          valueListenable: _rt.session,
          builder: (context, s, _) => GlassSurface(
            weight: GlassWeight.lens,
            radius: Radii.pane,
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              children: [
                GlassSlider(
                  label: 'Steps',
                  value: s.sampling.steps.toDouble(),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  tint: Palette.iris,
                  format: (v) => v.round().toString(),
                  onChanged: (v) => _rt.session
                      .tuneSampling((p) => p.copyWith(steps: v.round())),
                ),
                const SizedBox(height: Space.lg),
                GlassSlider(
                  label: 'CFG Scale',
                  value: s.sampling.cfgScale,
                  min: 1,
                  max: 15,
                  tint: Palette.ember,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) =>
                      _rt.session.tuneSampling((p) => p.copyWith(cfgScale: v)),
                ),
                const SizedBox(height: Space.lg),
                GlassSegmented<int>(
                  value: s.sampling.width,
                  tint: Palette.iris,
                  onChanged: (v) => _rt.session.tuneSampling(
                    (p) => p.copyWith(width: v, height: v),
                  ),
                  segments: const [
                    GlassSegment(value: 512, label: '512'),
                    GlassSegment(value: 768, label: '768'),
                    GlassSegment(value: 1024, label: '1024'),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Row(
                  children: [
                    Expanded(child: Text('Random seed', style: Type.label)),
                    GlassSwitch(
                      value: s.sampling.isSeedRandom,
                      tint: Palette.iris,
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
        ),
        const SizedBox(height: Space.xl),

        // ===== Run ===== //
        ValueListenableBuilder<RunState>(
          valueListenable: _rt.run,
          builder: (context, run, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: run.isActive ? 'Generating…' : 'Generate',
                      icon: Icons.auto_awesome_rounded,
                      tint: Palette.iris,
                      filled: true,
                      onPressed: (!_ready || run.isActive) ? null : _generate,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  GlassButton(
                    label: 'Stop',
                    icon: Icons.stop_rounded,
                    tint: Palette.alert,
                    onPressed: run.isActive ? _rt.cancelRun : null,
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              _RunReadout(run: run),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),

        // ===== Result ===== //
        Text('LIBRARY', style: Type.micro),
        const SizedBox(height: Space.md),
        ValueListenableBuilder(
          valueListenable: _rt.library,
          builder: (context, lib, _) {
            final image = lib.selected;
            return GlassSurface(
              weight: GlassWeight.lens,
              radius: Radii.pane,
              padding: const EdgeInsets.all(Space.lg),
              child: image == null
                  ? SizedBox(
                      height: 120,
                      child: Center(
                        child: Text('Nothing generated yet',
                            style: Type.body.copyWith(color: Palette.chalk40)),
                      ),
                    )
                  : Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.well),
                          child: _preview(image),
                        ),
                        const SizedBox(height: Space.md),
                        Text('${lib.count} in library', style: Type.readout),
                      ],
                    ),
            );
          },
        ),
      ],
    );
  }

  /// Forge hands back data URLs, ComfyUI hands back `/view` URLs; both end
  /// up in the same library, so both have to render here.
  Widget _preview(GeneratedImage image) => image.isDataUrl
      ? Image.memory(
          base64Decode(image.url.substring(image.url.indexOf(',') + 1)),
          fit: BoxFit.contain,
        )
      : Image.network(image.url, fit: BoxFit.contain);
}

class _StatusLine extends StatelessWidget {
  final String text;
  final bool ok;
  const _StatusLine({required this.text, required this.ok});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? Palette.iris : Palette.chalk40,
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            text,
            style: Type.body.copyWith(
              fontSize: 12.5,
              color: ok ? Palette.chalk70 : Palette.chalk40,
            ),
          ),
        ),
      ],
    );
  }
}

class _RunReadout extends StatelessWidget {
  final RunState run;
  const _RunReadout({required this.run});

  @override
  Widget build(BuildContext context) {
    final p = run.progress;
    return GlassSurface(
      weight: GlassWeight.vapor,
      radius: Radii.well,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        children: [
          _row('phase', p.stage ?? p.phase.label),
          _row('percent', p.percent == null ? '—' : '${p.percent}%'),
          _row('step',
              p.stepTotal == null ? '—' : '${p.stepCurrent ?? 0}/${p.stepTotal}'),
          if (p.failureMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                p.failureMessage!,
                style: Type.body.copyWith(fontSize: 12, color: Palette.alert),
              ),
            ),
          if (p.preview != null) ...[
            const SizedBox(height: Space.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.well),
              child: Image.memory(p.preview!, height: 160, fit: BoxFit.contain),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: Type.body
                      .copyWith(fontSize: 12.5, color: Palette.chalk40)),
            ),
            Text(value, style: Type.readout),
          ],
        ),
      );
}
