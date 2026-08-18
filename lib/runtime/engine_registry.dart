// ==================== Engine Registry ==================== //

import 'dart:async';

import 'package:sd_companion/data/engines/comfy/comfy_engine.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/data/engines/forge/forge_engine.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/engine/image_engine.dart';

/// Keeps one live [ImageEngine] per [EngineKind], rebuilt when its address
/// changes.
///
/// The old `BackendManager` held a single `activeBackend` and swapped it in
/// place, so switching to ComfyUI tore down Forge's state and switching back
/// rebuilt it from scratch. Worse, both backends read their host from the
/// same globals, so the two could never be configured independently. Here
/// each kind keeps its own instance and its own endpoint, and a switch is
/// just a lookup.
///
/// The registry is deliberately *not* a singleton: the runtime owns it, so a
/// test can build a registry pointed at a fake server without touching
/// anything global.
class EngineRegistry {
  /// Injected so a test can hand back a stub without a live server.
  final ImageEngine Function(EngineEndpoint endpoint)? engineFactory;

  /// One workflow service per ComfyUI endpoint. Workflows are per-server
  /// (saved under the endpoint id), so sharing one across two servers would
  /// show machine A's workflows while pointed at machine B.
  final Map<String, ComfyWorkflowService> _workflowServices = {};

  final Map<String, ImageEngine> _engines = {};

  EngineRegistry({this.engineFactory});

  /// The engine for [endpoint], created on first use and reused after.
  ImageEngine of(EngineEndpoint endpoint) =>
      _engines.putIfAbsent(endpoint.id, () => _build(endpoint));

  /// The workflow service backing a ComfyUI [endpoint].
  ComfyWorkflowService workflowsFor(EngineEndpoint endpoint) =>
      _workflowServices.putIfAbsent(endpoint.id, ComfyWorkflowService.new);

  ImageEngine _build(EngineEndpoint endpoint) {
    final custom = engineFactory;
    if (custom != null) return custom(endpoint);

    return switch (endpoint.kind) {
      EngineKind.forge => ForgeEngine(endpoint: endpoint),
      EngineKind.comfy => ComfyEngine(
          endpoint: endpoint,
          workflows: workflowsFor(endpoint),
        ),
    };
  }

  /// Drops the engine for [endpoint] so the next lookup rebuilds it. Called
  /// when the user edits an address - the old instance holds a socket and a
  /// poll timer pointed at the previous host.
  Future<void> invalidate(EngineEndpoint endpoint) async {
    await _engines.remove(endpoint.id)?.dispose();
  }

  Future<void> dispose() async {
    final engines = _engines.values.toList();
    _engines.clear();
    _workflowServices.clear();
    for (final engine in engines) {
      await engine.dispose();
    }
  }
}
