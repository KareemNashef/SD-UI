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

const _widgetPrimitiveTypes = {'INT', 'FLOAT', 'STRING', 'BOOLEAN'};

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

      if (options['control_after_generate'] == true) {
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
