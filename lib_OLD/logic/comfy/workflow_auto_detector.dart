// ==================== Workflow Auto Detector ==================== //
//
// Replaces the favoritedWidgets-based approach: instead of requiring the
// user to mark widgets in ComfyUI's own editor, this walks the graph
// structurally to find the settings that matter, using only input/output
// *types* and generic node-shape signatures - never a per-node-type name
// allowlist, so arbitrary custom nodes (Nunchaku loaders, GGUF loaders,
// Krea2 edit nodes, inpaint-crop packs, ...) all work unmodified.
//
// Algorithm, in short:
// 1. Find "the sampler": the active node with `positive`/`negative`
//    CONDITIONING inputs and a LATENT output (KSampler-shaped).
// 2. Trace its `positive`/`negative` inputs back through any conditioning
//    passthrough/combiner nodes (InpaintModelConditioning, etc.) to the
//    node that actually owns an editable STRING widget. If both roles
//    resolve to the *same* node (e.g. a real prompt run through
//    ConditioningZeroOut for a no-op negative), only positive counts -
//    there is no distinct negative to expose.
// 3. From the positive prompt's node, trace its CLIP input back to the
//    CLIP loader; from the sampler's MODEL input, trace back to the model
//    loader; from a VAEDecode-shaped node's VAE input, trace back to the
//    VAE loader. All three traces walk through any number of same-type
//    "patch" nodes (LoRA, ModelSamplingAuraFlow, CFGNorm, Differential
//    Diffusion, ...) by matching the link's *output name* to an
//    identically-typed input name, falling back to "the first input of
//    that type" when names don't match (very common - e.g. CFGNorm's
//    output is named `patched_model` but its input is `model`).
// 4. Trace the sampler's `latent_image` input back the same way. If it
//    terminates at a node with width/height/batch-style widgets (an empty
//    latent generator), those become the latent settings. If it
//    terminates at an image encoder instead (VAEEncode, an inpaint-crop
//    node, ...), there are no such widgets to find, which is exactly
//    right: an img2img/inpaint workflow's canvas size comes from the
//    input image, not a user-set width/height.
// 5. Find image-upload-capable nodes generically via the `image_upload`
//    metadata flag ComfyUI itself puts on `LoadImage`-shaped widgets - no
//    node-type-name check needed. The first is primary, the rest are
//    additional slots. If the primary loader's MASK output is actually
//    wired to something, the workflow supports mask painting.

import 'package:sd_companion/logic/comfy/comfy_node_schema.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow.dart';

enum DetectedRole {
  positivePrompt,
  negativePrompt,
  primaryImage,
  additionalImage,
  model,
  clip,
  vae,
  sampler,
  latent,
}

class DetectedWidget {
  final DetectedRole role;
  final ComfyEditorNode node;
  final ComfyInputSpec input;
  final int? widgetSlotIndex;
  final dynamic currentValue;

  /// True when this widget-capable input currently has an active link (i.e.
  /// its value is actually computed by an upstream node, such as a
  /// ResolutionSelector feeding an EmptyLatentImage's width/height). Its
  /// `currentValue` reflects the frozen widgets_values, not the live
  /// upstream value, so it must be shown read-only, not edited directly.
  final bool isLinked;

  /// For a `seed`-shaped widget flagged `control_after_generate` in its
  /// schema: the slot index/current value of the synthetic companion widget
  /// (`fixed`/`randomize`/`increment`/`decrement`) the ComfyUI frontend
  /// injects right after it. Null for every other widget.
  final int? controlAfterGenerateSlotIndex;
  final String? controlAfterGenerateValue;

  const DetectedWidget({
    required this.role,
    required this.node,
    required this.input,
    required this.widgetSlotIndex,
    required this.currentValue,
    this.isLinked = false,
    this.controlAfterGenerateSlotIndex,
    this.controlAfterGenerateValue,
  });

  bool get isRandomized => controlAfterGenerateValue == 'randomize';

  String get label => node.title ?? node.type;
}

class DetectedWorkflowSettings {
  final DetectedWidget? positivePrompt;
  final DetectedWidget? negativePrompt;
  final List<DetectedWidget> images; // [0] is primary when non-empty
  final bool maskSupported;
  final ComfyEditorNode? maskSourceNode;
  final List<DetectedWidget> modelSettings;
  final List<DetectedWidget> clipSettings;
  final List<DetectedWidget> vaeSettings;
  final List<DetectedWidget> samplerSettings;
  final List<DetectedWidget> latentSettings;
  final List<String> warnings;

  const DetectedWorkflowSettings({
    required this.positivePrompt,
    required this.negativePrompt,
    required this.images,
    required this.maskSupported,
    required this.maskSourceNode,
    required this.modelSettings,
    required this.clipSettings,
    required this.vaeSettings,
    required this.samplerSettings,
    required this.latentSettings,
    required this.warnings,
  });

  factory DetectedWorkflowSettings.empty(List<String> warnings) =>
      DetectedWorkflowSettings(
        positivePrompt: null,
        negativePrompt: null,
        images: const [],
        maskSupported: false,
        maskSourceNode: null,
        modelSettings: const [],
        clipSettings: const [],
        vaeSettings: const [],
        samplerSettings: const [],
        latentSettings: const [],
        warnings: warnings,
      );

  DetectedWidget? get primaryImage => images.isEmpty ? null : images.first;
  List<DetectedWidget> get additionalImages =>
      images.length <= 1 ? const [] : images.sublist(1);
}

class WorkflowAutoDetector {
  final ComfyNodeSchemaProvider schemaProvider;
  const WorkflowAutoDetector(this.schemaProvider);

  Future<DetectedWorkflowSettings> detect(ComfyWorkflowDocument doc) async {
    final warnings = <String>[];

    final samplerNode = await _findSamplerNode(doc);
    if (samplerNode == null) {
      return DetectedWorkflowSettings.empty([
        'No sampling node found (expected an active node with "positive"/"negative" '
            'conditioning inputs and a latent output, e.g. KSampler)',
      ]);
    }
    final samplerSchema = await schemaProvider.schemaFor(samplerNode.type);

    // ---- Prompt detection ----
    ComfyEditorNode? positiveSource;
    ComfyEditorNode? negativeSource;
    positiveSource = await _traceInput(doc, samplerNode, samplerSchema, 'positive', 'CONDITIONING');
    negativeSource = await _traceInput(doc, samplerNode, samplerSchema, 'negative', 'CONDITIONING');

    DetectedWidget? positivePrompt;
    DetectedWidget? negativePrompt;
    ComfyEditorNode? positiveEncoderNode;
    ComfyNodeSchema? positiveEncoderSchema;

    if (positiveSource != null) {
      final schema = await schemaProvider.schemaFor(positiveSource.type);
      final textInput = schema.firstTextWidget();
      if (textInput != null) {
        positivePrompt = _build(DetectedRole.positivePrompt, positiveSource, schema, textInput);
        positiveEncoderNode = positiveSource;
        positiveEncoderSchema = schema;
      }
    }
    if (negativeSource != null &&
        (positiveSource == null || negativeSource.id != positiveSource.id)) {
      final schema = await schemaProvider.schemaFor(negativeSource.type);
      final textInput = schema.firstTextWidget();
      if (textInput != null) {
        negativePrompt = _build(DetectedRole.negativePrompt, negativeSource, schema, textInput);
      }
    }
    if (positivePrompt == null) {
      warnings.add('Could not find an editable prompt widget feeding the sampler');
    }

    // ---- Model chain: just the model file itself, not loader internals
    // (weight_dtype, cpu_offload, ...) - it's always the first widget a
    // loader declares. ----
    final modelSettings = <DetectedWidget>[];
    final modelSource = await _traceInput(doc, samplerNode, samplerSchema, 'model', 'MODEL');
    if (modelSource != null) {
      final schema = await schemaProvider.schemaFor(modelSource.type);
      final widgetInputs = schema.inputs.where((i) => i.isWidgetCapable).toList();
      if (widgetInputs.isNotEmpty) {
        modelSettings.add(_build(DetectedRole.model, modelSource, schema, widgetInputs.first));
      }
    } else {
      warnings.add('Could not trace the sampler\'s model input to a loader');
    }

    // ---- CLIP chain (from the positive prompt's encoder node): loader
    // file + type, not secondary options like `device`. ----
    final clipSettings = <DetectedWidget>[];
    if (positiveEncoderNode != null && positiveEncoderSchema != null) {
      final clipSource = await _traceInput(
        doc,
        positiveEncoderNode,
        positiveEncoderSchema,
        'clip',
        'CLIP',
      );
      if (clipSource != null) {
        final schema = await schemaProvider.schemaFor(clipSource.type);
        final widgetInputs = schema.inputs.where((i) => i.isWidgetCapable).toList();
        for (final input in widgetInputs.take(2)) {
          clipSettings.add(_build(DetectedRole.clip, clipSource, schema, input));
        }
      }
    }

    // ---- VAE chain (from a VAEDecode-shaped node): just the file. ----
    final vaeSettings = <DetectedWidget>[];
    final vaeDecodeNode = await _findVaeDecodeNode(doc);
    if (vaeDecodeNode != null) {
      final decSchema = await schemaProvider.schemaFor(vaeDecodeNode.type);
      final vaeSource = await _traceInput(doc, vaeDecodeNode, decSchema, 'vae', 'VAE');
      if (vaeSource != null) {
        final schema = await schemaProvider.schemaFor(vaeSource.type);
        final widgetInputs = schema.inputs.where((i) => i.isWidgetCapable).toList();
        if (widgetInputs.isNotEmpty) {
          vaeSettings.add(_build(DetectedRole.vae, vaeSource, schema, widgetInputs.first));
        }
      }
    }

    // ---- Sampler's own widgets (seed/steps/cfg/sampler/scheduler/denoise) ----
    final samplerSettings = [
      for (final input in samplerSchema.inputs.where((i) => i.isWidgetCapable))
        _build(DetectedRole.sampler, samplerNode, samplerSchema, input),
    ];

    // ---- Latent settings (only present for empty-latent-style sources) ----
    var latentSettings = <DetectedWidget>[];
    final latentSource = await _traceInput(doc, samplerNode, samplerSchema, 'latent_image', 'LATENT');
    if (latentSource != null) {
      final schema = await schemaProvider.schemaFor(latentSource.type);
      for (final input in schema.inputs.where((i) => i.isWidgetCapable)) {
        latentSettings.add(_build(DetectedRole.latent, latentSource, schema, input));
      }
    }
    // Some workflows drive width/height from a dedicated node (e.g. a
    // "Resolution Selector" with an aspect-ratio/megapixels combo) instead
    // of setting them directly. When a latent widget is linked, swap it for
    // its upstream source node's own widgets instead of a dead "linked,
    // read-only" row - that source node is what's actually editable.
    latentSettings = await _unwrapLinkedWidgets(doc, latentSettings, DetectedRole.latent);

    // ---- Images + mask ----
    final imageNodes = await _findImageUploadNodes(doc);
    final images = <DetectedWidget>[];
    for (var i = 0; i < imageNodes.length; i++) {
      final node = imageNodes[i];
      final schema = await schemaProvider.schemaFor(node.type);
      ComfyInputSpec? uploadInput;
      for (final input in schema.inputs) {
        if (input.options['image_upload'] == true) {
          uploadInput = input;
          break;
        }
      }
      if (uploadInput == null) continue;
      images.add(_build(
        i == 0 ? DetectedRole.primaryImage : DetectedRole.additionalImage,
        node,
        schema,
        uploadInput,
      ));
    }

    var maskSupported = false;
    ComfyEditorNode? maskSourceNode;
    if (imageNodes.isNotEmpty) {
      final primary = imageNodes.first;
      final schema = await schemaProvider.schemaFor(primary.type);
      final maskSlot = schema.outputTypes.indexOf('MASK');
      if (maskSlot != -1) {
        final rawOutputs = primary.outputs;
        if (maskSlot < rawOutputs.length) {
          final links = rawOutputs[maskSlot]['links'] as List?;
          if (links != null && links.isNotEmpty) {
            maskSupported = true;
            maskSourceNode = primary;
          }
        }
      }
    }

    return DetectedWorkflowSettings(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      images: images,
      maskSupported: maskSupported,
      maskSourceNode: maskSourceNode,
      modelSettings: modelSettings,
      clipSettings: clipSettings,
      vaeSettings: vaeSettings,
      samplerSettings: samplerSettings,
      latentSettings: latentSettings,
      warnings: warnings,
    );
  }

  /// Replaces any linked (non-editable) widget in [widgets] with its
  /// upstream source node's own widget-capable inputs, deduplicated so a
  /// node feeding multiple linked widgets (e.g. a ResolutionSelector's
  /// width+height outputs) only contributes its controls once. Widgets that
  /// aren't linked, or whose source has nothing editable of its own, are
  /// kept as-is.
  Future<List<DetectedWidget>> _unwrapLinkedWidgets(
    ComfyWorkflowDocument doc,
    List<DetectedWidget> widgets,
    DetectedRole role,
  ) async {
    final result = <DetectedWidget>[];
    final seenSourceNodeIds = <int>{};

    for (final widget in widgets) {
      if (!widget.isLinked) {
        result.add(widget);
        continue;
      }
      final entry = widget.node.inputEntry(widget.input.name);
      final link = entry != null && entry['link'] != null ? _linkById(doc, entry['link'] as num) : null;
      final sourceNode = link != null ? doc.nodeById(link.originNodeId) : null;
      if (sourceNode == null || !sourceNode.isActive) {
        result.add(widget);
        continue;
      }
      if (seenSourceNodeIds.contains(sourceNode.id)) continue; // already unwrapped
      final sourceSchema = await schemaProvider.schemaFor(sourceNode.type);
      final ownWidgets = sourceSchema.inputs.where((i) => i.isWidgetCapable).toList();
      if (ownWidgets.isEmpty) {
        result.add(widget);
        continue;
      }
      seenSourceNodeIds.add(sourceNode.id);
      for (final input in ownWidgets) {
        result.add(_build(role, sourceNode, sourceSchema, input));
      }
    }
    return result;
  }

  // ===== Graph walking helpers ===== //

  DetectedWidget _build(
    DetectedRole role,
    ComfyEditorNode node,
    ComfyNodeSchema schema,
    ComfyInputSpec input,
  ) {
    final slotIndex = schema.widgetSlotIndex(input.name);
    final values = node.widgetsValues;
    final value = (slotIndex != null && slotIndex < values.length)
        ? values[slotIndex]
        : input.options['default'];
    final entry = node.inputEntry(input.name);
    final isLinked = entry != null && entry['link'] != null;

    int? controlSlotIndex;
    String? controlValue;
    if (input.options['control_after_generate'] == true) {
      controlSlotIndex = schema.widgetSlotIndex('${input.name}.control_after_generate');
      if (controlSlotIndex != null && controlSlotIndex < values.length) {
        controlValue = values[controlSlotIndex]?.toString();
      }
    }

    return DetectedWidget(
      role: role,
      node: node,
      input: input,
      widgetSlotIndex: slotIndex,
      currentValue: value,
      isLinked: isLinked,
      controlAfterGenerateSlotIndex: controlSlotIndex,
      controlAfterGenerateValue: controlValue,
    );
  }

  /// Resolves [node]'s input named [inputName] (falling back to the first
  /// input of [socketType] if the exact name isn't found - custom nodes
  /// don't always use the conventional name) and traces it to its source.
  Future<ComfyEditorNode?> _traceInput(
    ComfyWorkflowDocument doc,
    ComfyEditorNode node,
    ComfyNodeSchema schema,
    String inputName,
    String socketType,
  ) async {
    final input = schema.inputByName(inputName) ?? schema.firstSocketOfType(socketType);
    if (input == null) return null;
    final entry = node.inputEntry(input.name);
    if (entry == null || entry['link'] == null) return null;
    final link = _linkById(doc, entry['link'] as num);
    if (link == null) return null;
    return _traceToSource(doc, link.originNodeId, link.originSlot, socketType);
  }

  Future<ComfyEditorNode?> _traceToSource(
    ComfyWorkflowDocument doc,
    int nodeId,
    int outputSlot, // ignore: unused element warning guard
    String socketType, {
    int depth = 0,
  }) async {
    if (depth > 16) return null;
    final node = doc.nodeById(nodeId);
    if (node == null || !node.isActive) return null;
    final schema = await schemaProvider.schemaFor(node.type);
    if (!schema.known) return node; // best-effort terminus for unknown nodes

    final outputName = (outputSlot >= 0 && outputSlot < schema.outputNames.length)
        ? schema.outputNames[outputSlot]
        : null;
    final continuation = schema.firstSocketOfType(socketType, preferredName: outputName);
    if (continuation == null) return node; // terminus: no same-type input to follow

    final entry = node.inputEntry(continuation.name);
    if (entry == null || entry['link'] == null) return node; // dangling: stop here

    final link = _linkById(doc, entry['link'] as num);
    if (link == null) return node;

    return _traceToSource(doc, link.originNodeId, link.originSlot, socketType, depth: depth + 1);
  }

  ComfyEditorLink? _linkById(ComfyWorkflowDocument doc, num id) {
    for (final link in doc.links) {
      if (link.id == id.toInt()) return link;
    }
    return null;
  }

  Future<ComfyEditorNode?> _findSamplerNode(ComfyWorkflowDocument doc) async {
    for (final node in doc.nodes.where((n) => n.isActive)) {
      final schema = await schemaProvider.schemaFor(node.type);
      if (!schema.known) continue;
      final hasPositive = schema.inputs.any(
        (i) => !i.isWidgetCapable && i.type == 'CONDITIONING' && i.name.toLowerCase() == 'positive',
      );
      final hasNegative = schema.inputs.any(
        (i) => !i.isWidgetCapable && i.type == 'CONDITIONING' && i.name.toLowerCase() == 'negative',
      );
      final hasLatentOut = schema.outputTypes.contains('LATENT');
      // A real sampler *consumes* a starting latent (`latent_image`) as well
      // as producing one - this is what distinguishes it from a conditioning
      // combiner/re-router like InpaintModelConditioning, which also exposes
      // positive/negative CONDITIONING inputs and a LATENT output but has no
      // LATENT input at all.
      final hasLatentIn = schema.inputs.any((i) => !i.isWidgetCapable && i.type == 'LATENT');
      if (hasPositive && hasNegative && hasLatentOut && hasLatentIn) return node;
    }
    return null;
  }

  Future<ComfyEditorNode?> _findVaeDecodeNode(ComfyWorkflowDocument doc) async {
    for (final node in doc.nodes.where((n) => n.isActive)) {
      final schema = await schemaProvider.schemaFor(node.type);
      if (!schema.known) continue;
      final hasLatentIn = schema.inputs.any((i) => !i.isWidgetCapable && i.type == 'LATENT');
      final hasVaeIn = schema.inputs.any((i) => !i.isWidgetCapable && i.type == 'VAE');
      final hasImageOut = schema.outputTypes.contains('IMAGE');
      if (hasLatentIn && hasVaeIn && hasImageOut) return node;
    }
    return null;
  }

  Future<List<ComfyEditorNode>> _findImageUploadNodes(ComfyWorkflowDocument doc) async {
    final results = <ComfyEditorNode>[];
    for (final node in doc.nodes.where((n) => n.isActive)) {
      final schema = await schemaProvider.schemaFor(node.type);
      if (!schema.known) continue;
      final hasUpload = schema.inputs.any((i) => i.options['image_upload'] == true);
      if (hasUpload) results.add(node);
    }
    results.sort((a, b) => a.id.compareTo(b.id));
    return results;
  }
}
