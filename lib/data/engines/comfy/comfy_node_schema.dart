// ==================== Comfy Node Schema ==================== //
//
// Wraps a single node type's `/object_info` entry and reproduces the two
// ComfyUI frontend rules that matter for round-tripping `widgets_values`:
//
// 1. An input becomes a *widget slot* (i.e. occupies a widgets_values array
//    position) iff its declared type is one of the primitive widget types
//    (INT/FLOAT/STRING/BOOLEAN) or a combo (array of options) - regardless
//    of whether it currently has a link. Every other type (MODEL, LATENT,
//    IMAGE, MASK, CLIP, VAE, CONDITIONING, custom socket types, ...) is
//    socket-only and never occupies a widgets_values slot.
// 2. The frontend injects synthetic widget slots that don't appear in
//    `/object_info` at all: an extra combo immediately after any INT widget
//    flagged `control_after_generate`, and an extra string immediately
//    after any combo flagged `image_upload` (the upload-mode picker).
//    Both slots exist in `widgets_values` but are never sent to `/prompt`.
//
// Verified against a live ComfyUI 0.33 server for KSampler, LoadImage,
// SaveImage, UNETLoader, CLIPLoader, VAELoader, VAEEncode, VAEDecode,
// LoraLoaderModelOnly, EmptySD3LatentImage, ResolutionSelector, and the
// custom Krea2EditGroundedEncode/Krea2EditModelPatch nodes - the resulting
// widgetSlots length matches widgets_values.length for every node in
// test/fixtures/krea2_identity_edit_workflow.json.

import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';

const _widgetPrimitiveTypes = {'INT', 'FLOAT', 'STRING', 'BOOLEAN'};

/// Where [widgetName] sits in *this node's* `widgets_values`, or null when
/// it has no slot there at all.
///
/// The schema alone is not enough, and the difference is not cosmetic. An
/// optional input of a primitive type is a widget by default, but a graph
/// can also declare it as a plain socket - and then the frontend gives it no
/// `widgets_values` entry, shifting everything after it by one. The two
/// cases look identical in `/object_info`; only the node tells them apart,
/// by whether its own `inputs` entry carries a `widget` marker:
///
///   * absent from `inputs`            -> an ordinary widget, has a slot
///   * present *with* `widget: {...}`  -> a widget converted to an input,
///                                        keeps its slot (`ref_boost`)
///   * present *without* it            -> a socket, and has never had one
///                                        (`PromptGenerator.prompt_input`)
///
/// Reading the third case as a widget is how a prompt generator ends up
/// being sent the name of a model as its input text, with every widget after
/// it reading one place early.
int? widgetSlotIndexFor(
  ComfyNodeSchema schema,
  ComfyEditorNode node,
  String widgetName,
) {
  var index = 0;
  for (final slot in schema.widgetSlots) {
    // Synthetic companions belong to the widget before them, and share its
    // fate; the base name is what the node knows about.
    final base = slot.name.split('.').first;
    if (isSocketOnly(node, base)) continue;
    if (slot.name == widgetName) return index;
    index++;
  }
  return null;
}

/// True when the graph declares [inputName] as a plain socket rather than a
/// widget - see [widgetSlotIndexFor].
bool isSocketOnly(ComfyEditorNode node, String inputName) {
  final entry = node.inputEntry(inputName);
  return entry != null && entry['widget'] == null;
}

class ComfyInputSpec {
  final String name;
  final String type; // 'COMBO' or a raw type string like 'MODEL', 'INT'
  final List<dynamic>? comboOptions;
  final Map<String, dynamic> options;
  final bool isRequired;
  final bool isWidgetCapable;

  const ComfyInputSpec({
    required this.name,
    required this.type,
    required this.isRequired,
    required this.isWidgetCapable,
    this.comboOptions,
    this.options = const {},
  });
}

class ComfyWidgetSlot {
  final String name; // input name, or 'name.control_after_generate' / 'name.upload'
  final String type;
  final List<dynamic>? comboOptions;
  final Map<String, dynamic> options;
  final bool synthetic;

  const ComfyWidgetSlot({
    required this.name,
    required this.type,
    required this.synthetic,
    this.comboOptions,
    this.options = const {},
  });
}

class ComfyNodeSchema {
  final String type;
  final List<ComfyInputSpec> inputs; // required+optional, ordered, no hidden
  final List<ComfyWidgetSlot> widgetSlots; // aligned to widgets_values indices
  final List<String> outputTypes; // e.g. ['CONDITIONING','CONDITIONING','LATENT']
  final List<String> outputNames; // e.g. ['positive','negative','latent']
  final bool outputNode;

  /// False when `/object_info` had no entry for this type: either a
  /// frontend-only decoration (e.g. `Note`) or a custom node whose
  /// definition failed to load.
  final bool known;

  const ComfyNodeSchema({
    required this.type,
    required this.inputs,
    required this.widgetSlots,
    required this.outputTypes,
    required this.outputNames,
    required this.outputNode,
    required this.known,
  });

  factory ComfyNodeSchema.unknown(String type) => ComfyNodeSchema(
    type: type,
    inputs: const [],
    widgetSlots: const [],
    outputTypes: const [],
    outputNames: const [],
    outputNode: false,
    known: false,
  );

  ComfyInputSpec? inputByName(String name) {
    for (final input in inputs) {
      if (input.name == name) return input;
    }
    return null;
  }

  /// The first non-widget (socket) required-or-optional input whose
  /// declared type matches [type], preferring one named [preferredName]
  /// (case-insensitive) when there are several. Used by the auto-detector
  /// to walk MODEL/CLIP/VAE/CONDITIONING/IMAGE/LATENT chains generically,
  /// since custom nodes rarely agree on naming (`model` vs `patched_model`).
  ComfyInputSpec? firstSocketOfType(String type, {String? preferredName}) {
    final candidates = inputs.where((i) => !i.isWidgetCapable && i.type == type);
    if (preferredName != null) {
      for (final c in candidates) {
        if (c.name.toLowerCase() == preferredName.toLowerCase()) return c;
      }
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Editable (widget-capable) STRING inputs, preferring ones named "prompt"
  /// or "text" - the two conventional names for the main text box on a
  /// text-encoder-shaped node.
  ComfyInputSpec? firstTextWidget() {
    final strings = inputs.where((i) => i.isWidgetCapable && i.type == 'STRING').toList();
    for (final preferred in const ['prompt', 'text']) {
      for (final s in strings) {
        if (s.name.toLowerCase() == preferred) return s;
      }
    }
    return strings.isEmpty ? null : strings.first;
  }

  int? widgetSlotIndex(String widgetName) {
    for (var i = 0; i < widgetSlots.length; i++) {
      if (widgetSlots[i].name == widgetName) return i;
    }
    return null;
  }

  factory ComfyNodeSchema.fromObjectInfo(String type, Map<String, dynamic> raw) {
    final inputSection = (raw['input'] as Map?)?.cast<String, dynamic>() ?? {};
    final required = (inputSection['required'] as Map?)?.cast<String, dynamic>() ?? {};
    final optional = (inputSection['optional'] as Map?)?.cast<String, dynamic>() ?? {};
    final order = (raw['input_order'] as Map?)?.cast<String, dynamic>() ?? {};
    final requiredOrder =
        (order['required'] as List?)?.cast<String>() ?? required.keys.toList();
    final optionalOrder =
        (order['optional'] as List?)?.cast<String>() ?? optional.keys.toList();

    final inputs = <ComfyInputSpec>[];
    final widgetSlots = <ComfyWidgetSlot>[];

    void process(String name, bool isRequired, Map<String, dynamic> table) {
      final spec = table[name];
      if (spec is! List || spec.isEmpty) return;
      final typeSpec = spec[0];
      final options = (spec.length > 1 && spec[1] is Map)
          ? (spec[1] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      // Two combo encodings exist in the wild: legacy nodes put the option
      // list directly in the type slot (`[["a","b"], {...}]`); newer nodes
      // (e.g. ResolutionSelector) use the literal type string "COMBO" with
      // the options nested under options['options'] instead.
      final isListCombo = typeSpec is List;
      final isNamedCombo = typeSpec == 'COMBO';
      final isCombo = isListCombo || isNamedCombo;
      final baseType = isCombo ? 'COMBO' : typeSpec.toString();
      final widgetCapable =
          isCombo || _widgetPrimitiveTypes.contains(baseType);
      final comboOptions = isListCombo
          ? List<dynamic>.from(typeSpec)
          : (isNamedCombo && options['options'] is List
                ? List<dynamic>.from(options['options'] as List)
                : null);

      inputs.add(
        ComfyInputSpec(
          name: name,
          type: baseType,
          comboOptions: comboOptions,
          options: options,
          isRequired: isRequired,
          isWidgetCapable: widgetCapable,
        ),
      );

      if (!widgetCapable) return;

      widgetSlots.add(
        ComfyWidgetSlot(
          name: name,
          type: baseType,
          comboOptions: comboOptions,
          options: options,
          synthetic: false,
        ),
      );

      // ComfyUI's own frontend adds the "fixed/increment/decrement/randomize"
      // companion widget to ANY INT widget literally named "seed" or
      // "noise_seed", purely by name convention - independent of whether the
      // node's Python schema sets `control_after_generate: true` (that flag
      // is one way to opt in, not the only one; e.g. KSampler's schema sets
      // it explicitly, but plenty of custom nodes - SeedVR2TilingUpscaler
      // among them - rely on the name convention instead). Missing this
      // meant the exported workflow's widgets_values had one more entry
      // than this schema accounted for, silently shifting every widget
      // after "seed" onto the wrong value.
      final looksLikeSeedWidget =
          baseType == 'INT' && (name == 'seed' || name == 'noise_seed');
      if (options['control_after_generate'] == true || looksLikeSeedWidget) {
        widgetSlots.add(
          ComfyWidgetSlot(
            name: '$name.control_after_generate',
            type: 'COMBO',
            comboOptions: const ['fixed', 'increment', 'decrement', 'randomize'],
            synthetic: true,
          ),
        );
      }
      if (options['image_upload'] == true) {
        widgetSlots.add(
          ComfyWidgetSlot(name: '$name.upload', type: 'STRING', synthetic: true),
        );
      }
    }

    for (final name in requiredOrder) {
      process(name, true, required);
    }
    for (final name in optionalOrder) {
      process(name, false, optional);
    }

    final outputTypes = (raw['output'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final outputNames = (raw['output_name'] as List?)?.map((e) => e.toString()).toList() ?? outputTypes;

    return ComfyNodeSchema(
      type: type,
      inputs: inputs,
      widgetSlots: widgetSlots,
      outputTypes: outputTypes,
      outputNames: outputNames,
      outputNode: raw['output_node'] == true,
      known: true,
    );
  }
}

/// Resolves and caches [ComfyNodeSchema] by node type.
abstract class ComfyNodeSchemaProvider {
  Future<ComfyNodeSchema> schemaFor(String nodeType);
}

/// Loads schemas from a static, pre-fetched `/object_info` map. Used by
/// tests (see test/fixtures/comfy_object_info.json) and as a cache layer.
class StaticComfyNodeSchemaProvider implements ComfyNodeSchemaProvider {
  final Map<String, dynamic> objectInfo;
  final Map<String, ComfyNodeSchema> _cache = {};

  StaticComfyNodeSchemaProvider(this.objectInfo);

  @override
  Future<ComfyNodeSchema> schemaFor(String nodeType) async {
    final cached = _cache[nodeType];
    if (cached != null) return cached;
    final raw = (objectInfo[nodeType] as Map?)?.cast<String, dynamic>();
    final schema = raw == null
        ? ComfyNodeSchema.unknown(nodeType)
        : ComfyNodeSchema.fromObjectInfo(nodeType, raw);
    _cache[nodeType] = schema;
    return schema;
  }
}
