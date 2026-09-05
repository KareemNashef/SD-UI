// ==================== Workflow Settings ==================== //
//
// Everything the active ComfyUI workflow exposes, as a page you can find
// things in.
//
// This was one flat scroll: five headings, every detected widget rendered
// full width in graph order, LoRAs at the bottom. A realistic Krea2 edit
// workflow produces seventeen controls plus a LoRA list, which came to
// roughly two thousand pixels of drawer - and every one of them looked
// equally important, so finding "steps" meant scrolling past the VAE loader
// and the CLIP type.
//
// Three things fix that, in order of how much they matter:
//
//  1. **Tabs.** Output, Sampling, Model, LoRAs. The grouping is the user's,
//     not the graph's: the latent node's widgets are "what shape is the
//     picture", the sampler's are "how hard do we work", the model chain
//     and the loaders are "what is doing the work".
//  2. **An Advanced fold per tab.** ComfyUI's own schema flags plumbing
//     with `advanced: true` (`multiple`, `weight_dtype`, `device`), and the
//     CLIP and VAE loaders are set once with the workflow and never touched
//     again. Both go behind one line instead of taking a row each.
//  3. **Help on demand.** Nodes ship tooltips - `ref_boost` explains the
//     whole fidelity dial - and nothing was showing them. One toggle in the
//     header reveals every one of them, so the page costs nothing when you
//     already know what a control does.
//
// The important design decision from the old build is unchanged: **nothing
// is hard-coded to width/height**. Workflows disagree about how resolution
// is expressed - a model trained on fixed buckets wants literal `width`/
// `height` ints, a graph built around a resolution-selector node wants
// `megapixels` plus `aspect_ratio` - so each widget is still drawn from its
// schema type and bounds, and only *which tab it lands on* is decided here.
//
// These values live in the workflow document, not in `SamplingParams`, so
// they are saved the moment they are edited and reloaded with the workflow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/data/engines/comfy/lora_manager_client.dart';
import 'package:sd_companion/data/engines/comfy/model_library.dart';
import 'package:sd_companion/data/engines/comfy/workflow_auto_detector.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';
import 'package:sd_companion/ui/stage/model_browser_page.dart';

/// Human names for the widget keys ComfyUI uses. Anything absent falls back
/// to a title-cased version of the raw key, so an unknown custom node still
/// reads sensibly instead of showing `cpu_offload`.
const Map<String, String> _friendlyLabels = {
  'unet_name': 'Model',
  'model_name': 'Model',
  'model_path': 'Model',
  'ckpt_name': 'Checkpoint',
  'clip_name': 'CLIP loader',
  'type': 'CLIP type',
  'vae_name': 'VAE',
  'seed': 'Seed',
  'noise_seed': 'Seed',
  'steps': 'Steps',
  'cfg': 'Guidance',
  'sampler_name': 'Sampler',
  'scheduler': 'Scheduler',
  'denoise': 'Denoise',
  'width': 'Width',
  'height': 'Height',
  'batch_size': 'Batch size',
  'aspect_ratio': 'Aspect ratio',
  'megapixels': 'Megapixels',
  'multiple': 'Multiple of',
  // Krea2 edit nodes: how strongly the reference image steers the
  // result. Detection is generic, so this only names it nicely.
  'ref_boost': 'Reference boost',
  'ref_boost_a': 'Scene boost',
  'fit_mode': 'Fit mode',
  'grounding_px': 'Grounding',
  'pre_cfg': 'Pre-CFG',
  'weight_dtype': 'Precision',
  'cpu_offload': 'CPU offload',
};

String friendlyLabel(String widgetName) {
  final known = _friendlyLabels[widgetName];
  if (known != null) return known;
  return widgetName
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class WidgetRange {
  final double min;
  final double max;
  final double? step;
  const WidgetRange(this.min, this.max, [this.step]);
}

/// Ranges narrowed from what the node declares. ComfyUI's bounds are the
/// limits of what the code accepts, not of what is worth generating -
/// `cfg` goes to 100 and `ref_boost` to 1000, which on a phone-width ruler
/// puts every useful value inside the first few pixels. These are the bands
/// people actually work in; the value is still clamped, not rewritten, so a
/// workflow saved outside the band keeps its value until the ruler is moved.
const Map<String, WidgetRange> narrowedRanges = {
  'cfg': WidgetRange(0, 10, 0.1),
  // Declared 1..10000. Below four nothing resolves and above fifty nothing
  // improves, so the other 9950 are travel with nothing at the end of it.
  'steps': WidgetRange(4, 50, 1),
  'megapixels': WidgetRange(0.5, 3, 0.1),
  // Krea2 edit nodes: 1 = reference off, 4 = the recommended likeness,
  // past ~10 the edit stops taking. Anything beyond 15 is dead travel.
  'ref_boost': WidgetRange(1, 15, 0.1),
  'ref_boost_a': WidgetRange(1, 15, 0.1),
};

/// The band a ruler should span, or null when the widget wants a number
/// field instead. ComfyUI reports a seed's range as [0, 2^64), which would
/// make a slider that moves billions per pixel.
WidgetRange? rulerRange(ComfyInputSpec input) {
  final narrowed = narrowedRanges[input.name];
  if (narrowed != null) return narrowed;
  final min = (input.options['min'] as num?)?.toDouble();
  final max = (input.options['max'] as num?)?.toDouble();
  if (min == null || max == null) return null;
  if ((max - min) > 10000 || max >= 1000000) return null;
  return WidgetRange(min, max, (input.options['step'] as num?)?.toDouble());
}

/// The step ladder for a numeric setting, coarse first.
///
/// The coarse step is picked so that crossing the useful range takes roughly
/// sixteen moves - fine enough to land on a value, coarse enough to get
/// across without a marathon - and each finer step is one the user reaches
/// by dragging away from the strip. The node's own step is the floor,
/// because a node that says it wants multiples of four means it.
List<double> stepLadder({
  required bool isInt,
  double? schemaStep,
  double? span,
}) {
  final floor = (schemaStep != null && schemaStep > 0)
      ? schemaStep
      : (isInt ? 1.0 : 0.01);
  if (isInt) {
    // An integer has one honest fine step - its floor - plus a coarse one
    // when the range is wide enough to need crossing.
    return (span != null && span <= 60) ? [floor] : [floor * 10, floor];
  }
  const candidates = [1.0, 0.5, 0.1, 0.05, 0.01];
  final usable = candidates.where((c) => c >= floor - 1e-9).toList();
  if (usable.isEmpty) return [floor];
  final target = span == null ? 0.5 : span / 16;
  var start = usable.indexWhere((c) => c <= target);
  if (start < 0) start = usable.length - 1;
  return usable.sublist(start).take(3).toList();
}

/// How many decimals a value needs, given the finest step it can take.
int decimalsFor(double step) => step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);

/// `8`, `7.5`, `0.05` - never `8.00`. Trailing zeros on a tape full of tick
/// labels are pure noise, and the readout should match the ticks.
String trimNumber(double value, int decimals) {
  var text = value.toStringAsFixed(decimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}

// ===== What goes where ===== //

enum SettingsTab {
  output('Output'),
  sampling('Sampling'),
  model('Model'),
  loras('LoRAs');

  final String label;
  const SettingsTab(this.label);
}

/// Settings that belong behind the fold rather than on the face of a tab.
///
/// Two signals, both of them somebody else's judgement rather than a list
/// maintained here: ComfyUI's schema marks plumbing `advanced` (the
/// resolution selector's `multiple`, a loader's `weight_dtype`), and the
/// CLIP and VAE loaders are chosen once when the workflow is built and then
/// never touched - changing either is how you break a workflow, not how you
/// tune one.
bool isAdvancedSetting(DetectedWidget widget) =>
    widget.input.options['advanced'] == true ||
    widget.role == DetectedRole.clip ||
    widget.role == DetectedRole.vae;

/// Every setting the given tab shows, in the order it shows them.
///
/// The Model tab is the one that needs de-duplicating. A
/// `CheckpointLoaderSimple` emits MODEL, CLIP and VAE from a single node, so
/// the detector - which traces each of those chains separately, as it must -
/// arrives at the same `ckpt_name` widget three times. Rendered literally
/// that is three identical "Checkpoint" rows, two of them lies.
List<DetectedWidget> settingsForTab(
  SettingsTab tab,
  DetectedWorkflowSettings detected,
) =>
    switch (tab) {
      SettingsTab.output => detected.latentSettings,
      SettingsTab.sampling => detected.samplerSettings,
      SettingsTab.model => _distinct([
          ...detected.modelSettings,
          ...detected.clipSettings,
          ...detected.vaeSettings,
        ]),
      SettingsTab.loras => const [],
    };

/// One row per widget, keeping the first (and therefore least buried)
/// appearance of each.
List<DetectedWidget> _distinct(List<DetectedWidget> settings) {
  final seen = <String>{};
  return [
    for (final setting in settings)
      if (seen.add('${setting.node.id}:${setting.input.name}')) setting,
  ];
}

/// Tabs with something on them. A txt2img graph has no LoRA loader; an
/// img2img one has no latent settings at all, because its size comes from
/// the input image. Showing empty tabs would be worse than the flat list
/// this replaces.
List<SettingsTab> tabsFor(DetectedWorkflowSettings detected) => [
      for (final tab in SettingsTab.values)
        if (tab == SettingsTab.loras
            ? (detected.loras.isNotEmpty || detected.canEditLoras)
            : settingsForTab(tab, detected).isNotEmpty)
          tab,
    ];

// ===== The page ===== //

/// Opens the settings for the active workflow.
Future<void> openWorkflowSettings(
  BuildContext context, {
  required ComfyWorkflowService workflows,
  required ModelLibrary library,
  required String title,
}) =>
    Navigator.of(context).push<void>(
      DeskPageRoute(
        builder: (_) => WorkflowSettingsPage(
          workflows: workflows,
          library: library,
          title: title,
        ),
        fullscreenDialog: true,
      ),
    );

class WorkflowSettingsPage extends StatefulWidget {
  final ComfyWorkflowService workflows;

  /// The server's checkpoint/LoRA library. Model and LoRA settings are
  /// picked from it visually rather than from a list of filenames.
  final ModelLibrary library;

  final String title;

  const WorkflowSettingsPage({
    super.key,
    required this.workflows,
    required this.library,
    required this.title,
  });

  @override
  State<WorkflowSettingsPage> createState() => _WorkflowSettingsPageState();
}

class _WorkflowSettingsPageState extends State<WorkflowSettingsPage> {
  SettingsTab _tab = SettingsTab.output;

  /// Whether to print each control's own description under it. Off by
  /// default: once you know what Guidance does, a paragraph under every
  /// row is the crowding this page exists to remove.
  bool _help = false;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Desk(
      mode: brightness == Brightness.dark ? DeskMode.night : DeskMode.day,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                widget.workflows.activeDetected,
                widget.workflows.activeError,
                widget.workflows.activeWorkflowId,
              ]),
              builder: (context, _) => _content(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final p = DeskTheme.of(context);
    final detected = widget.workflows.activeDetected.value;
    final error = widget.workflows.activeError.value;

    final header = DeskPageHeader(
      title: widget.title,
      onClose: () => Navigator.of(context).pop(),
      action: detected == null
          ? null
          : DeskButton(
              // A constant label: swapping it for "Hide help" resizes the
              // button under the finger that just pressed it.
              label: 'Help',
              icon: Icons.help_outline_rounded,
              kind: _help ? DeskButtonKind.primary : DeskButtonKind.secondary,
              onPressed: () => setState(() => _help = !_help),
            ),
    );

    if (error != null) {
      return Column(children: [header, _message(p, error, isError: true)]);
    }
    if (detected == null) {
      return Column(
        children: [header, _message(p, 'No workflow analysed yet.')],
      );
    }

    final tabs = tabsFor(detected);
    if (tabs.isEmpty) {
      return Column(
        children: [
          header,
          _message(p, 'This workflow exposes no editable settings.'),
        ],
      );
    }
    // A tab can vanish under you - removing the last LoRA takes its tab
    // with it - so the selection is validated against what exists now
    // rather than trusted from the last build.
    final tab = tabs.contains(_tab) ? _tab : tabs.first;

    return Column(
      children: [
        header,
        Padding(
          padding:
              const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
          child: DeskTabStrip<SettingsTab>(
            value: tab,
            onChanged: (next) => setState(() => _tab = next),
            tabs: [for (final t in tabs) DeskTab(value: t, label: t.label)],
          ),
        ),
        // The tabs sit on this line the way folder tabs sit on a folder.
        Container(height: Stroke.standard, color: p.ink),
        Expanded(
          child: ListView(
            key: ValueKey(tab),
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, Space.lg, Space.gutter, Space.xxl),
            children: _body(tab, detected),
          ),
        ),
      ],
    );
  }

  Widget _message(DeskPalette p, String text, {bool isError = false}) =>
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Type.body
                  .copyWith(color: isError ? DeskPalette.alert : p.inkFaint),
            ),
          ),
        ),
      );

  List<Widget> _body(SettingsTab tab, DetectedWorkflowSettings detected) {
    if (tab == SettingsTab.loras) {
      return [
        _LoraSection(
          workflows: widget.workflows,
          library: widget.library,
          detected: detected,
        ),
      ];
    }

    final settings = settingsForTab(tab, detected);
    final primary = settings.where((s) => !isAdvancedSetting(s)).toList();
    final advanced = settings.where(isAdvancedSetting).toList();

    return [
      // Warnings are about the graph as a whole, so they go on whichever
      // tab opens first rather than being repeated on every one.
      if (tab == tabsFor(detected).first)
        for (final warning in detected.warnings) _warning(warning),
      for (final setting in primary) _control(setting),
      if (advanced.isNotEmpty)
        _AdvancedFold(
          count: advanced.length,
          children: [for (final setting in advanced) _control(setting)],
        ),
    ];
  }

  Widget _control(DetectedWidget setting) => Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: _DetectedWidgetControl(
          key: ValueKey('${setting.node.id}:${setting.input.name}'),
          workflows: widget.workflows,
          library: widget.library,
          detected: setting,
          showHelp: _help,
        ),
      );

  Widget _warning(String text) => Builder(
        builder: (context) {
          final p = DeskTheme.of(context);
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: DeskPalette.caution),
                const SizedBox(width: Space.sm),
                Expanded(
                  child:
                      Text(text, style: Type.body.copyWith(color: p.inkMuted)),
                ),
              ],
            ),
          );
        },
      );
}

/// One line that hides the settings nobody edits twice.
class _AdvancedFold extends StatefulWidget {
  final int count;
  final List<Widget> children;

  const _AdvancedFold({required this.count, required this.children});

  @override
  State<_AdvancedFold> createState() => _AdvancedFoldState();
}

class _AdvancedFoldState extends State<_AdvancedFold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: Stroke.hairline, color: p.ink.withValues(alpha: 0.2)),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Row(
              children: [
                Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: p.inkMuted),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text('ADVANCED',
                      style: Type.micro.copyWith(color: p.inkFaint)),
                ),
                Text('${widget.count}',
                    style: Type.micro.copyWith(color: p.inkFaint)),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}

/// One detected widget, drawn from its schema rather than from a guess about
/// what it is called.
class _DetectedWidgetControl extends StatefulWidget {
  final ComfyWorkflowService workflows;
  final ModelLibrary library;
  final DetectedWidget detected;
  final bool showHelp;

  const _DetectedWidgetControl({
    super.key,
    required this.workflows,
    required this.library,
    required this.detected,
    required this.showHelp,
  });

  @override
  State<_DetectedWidgetControl> createState() => _DetectedWidgetControlState();
}

class _DetectedWidgetControlState extends State<_DetectedWidgetControl> {
  TextEditingController? _text;

  bool _focused = false;

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  DetectedWidget get d => widget.detected;
  ComfyInputSpec get spec => d.input;

  Future<void> _commit(dynamic value) =>
      widget.workflows.updateDetectedSettingValue(d, value);

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    // The node's own words. ComfyUI ships these and nothing was reading
    // them, which is why `ref_boost` looked like a mystery number.
    final help = widget.showHelp
        ? ((spec.options['tooltip'] as String?) ?? '').trim()
        : '';
    if (help.isEmpty) return _control(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _control(p),
        const SizedBox(height: Space.xs),
        Text(help, style: Type.micro.copyWith(color: p.inkFaint)),
      ],
    );
  }

  Widget _control(DeskPalette p) {
    final label = friendlyLabel(spec.name);

    // A linked input's value is computed upstream (e.g. a resolution
    // selector feeding width/height). Showing an editable control would be
    // a lie - the graph overwrites it at run time.
    if (d.isLinked) {
      return _readOnly(
          p, label, '${d.currentValue}', 'SET BY ${d.label.toUpperCase()}');
    }

    final options = spec.comboOptions;

    // The checkpoint or diffusion model itself gets the browser, not a
    // dropdown: it is the one choice worth seeing thumbnails and base
    // models for, and the filenames alone rarely say which is which.
    if (d.role == DetectedRole.modelFile &&
        options != null &&
        options.isNotEmpty) {
      return ModelPickerTile(
        library: widget.library,
        kind: ManagedModelKind.checkpoint,
        label: label,
        value: '${d.currentValue}',
        options: [for (final option in options) '$option'],
        onChanged: _commit,
      );
    }

    if (options != null && options.isNotEmpty) {
      return DeskDropdown<String>(
        label: label,
        value: '${d.currentValue}',
        options: [
          for (final option in options)
            DeskOption(value: '$option', label: '$option'),
        ],
        onChanged: _commit,
      );
    }

    final type = spec.type.toUpperCase();

    if (type == 'BOOLEAN') {
      final value = d.currentValue == true;
      return Row(
        children: [
          Expanded(child: Text(label, style: Type.label.copyWith(color: p.ink))),
          DeskToggle(value: value, onChanged: _commit),
        ],
      );
    }

    if (type == 'INT' || type == 'FLOAT') {
      final isInt = type == 'INT';
      final current = (d.currentValue as num?)?.toDouble() ?? 0;

      final range = rulerRange(spec);
      if (range != null) {
        final steps = stepLadder(
          isInt: isInt,
          schemaStep: range.step,
          span: range.max - range.min,
        );
        final decimals = isInt ? 0 : decimalsFor(steps.last);
        return DeskTape(
          label: label,
          value: current,
          min: range.min,
          max: range.max,
          steps: steps,
          format: (v) => trimNumber(v, decimals),
          onChanged: (v) => _commit(isInt ? v.round() : v),
        );
      }

      // Unbounded (seed and friends): a plain number field. The randomise
      // switch rides in the label row rather than taking a row of its own -
      // it is part of what the seed *is*, and a separate line for it was
      // pure height.
      _text ??= TextEditingController(text: '${d.currentValue}');
      if (_text!.text != '${d.currentValue}' && !_focused) {
        _text!.text = '${d.currentValue}';
      }
      return Focus(
        onFocusChange: (f) => _focused = f,
        child: DeskField(
          label: label,
          controller: _text!,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (raw) {
            final parsed = isInt ? int.tryParse(raw) : double.tryParse(raw);
            if (parsed != null) _commit(parsed);
          },
          trailing: d.controlAfterGenerateSlotIndex == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('RANDOMISE',
                        style: Type.micro.copyWith(color: p.inkFaint)),
                    const SizedBox(width: Space.sm),
                    DeskToggle(
                      value: d.isRandomized,
                      onChanged: (v) =>
                          widget.workflows.updateSeedRandomFlag(d, v),
                    ),
                  ],
                ),
        ),
      );
    }

    // STRING and anything unrecognised.
    _text ??= TextEditingController(text: '${d.currentValue ?? ''}');
    return DeskField(label: label, controller: _text!, onChanged: _commit);
  }

  Widget _readOnly(DeskPalette p, String label, String value, String note) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: Type.micro.copyWith(color: p.inkFaint)),
          const SizedBox(height: Space.xs),
          Container(
            height: Space.touch,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
            decoration: BoxDecoration(
              color: p.paperEdge,
              borderRadius: BorderRadius.circular(Corner.control),
              border: Border.all(color: p.inkFaint, width: Stroke.standard),
            ),
            child: Text(value, style: Type.label.copyWith(color: p.inkMuted)),
          ),
          const SizedBox(height: Space.xs),
          Text(note, style: Type.micro.copyWith(color: p.inkFaint)),
        ],
      );
}

// ===== LoRAs ===== //

/// LoRAs are a list, not a fixed set of settings: adding one changes the
/// shape of the graph rather than the value of a widget, so they get a tab
/// of their own with an add button instead of appearing among the model
/// settings the loader happens to expose.
class _LoraSection extends StatelessWidget {
  final ComfyWorkflowService workflows;
  final ModelLibrary library;
  final DetectedWorkflowSettings detected;

  const _LoraSection({
    required this.workflows,
    required this.library,
    required this.detected,
  });

  /// Adding opens the browser first and splices the node afterwards, so a
  /// cancelled pick leaves the graph alone. The alternative - add something
  /// arbitrary, then change it - writes twice and leaves a stray node behind
  /// if the user backs out.
  Future<void> _add(BuildContext context) async {
    final options = detected.availableLoras;
    if (options.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pick = await pickModel(
      context,
      library: library,
      kind: ManagedModelKind.lora,
      options: options,
    );
    if (pick == null) return;
    try {
      await workflows.addLora(file: pick.option);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final noFiles = detected.availableLoras.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (detected.loras.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Text(
              noFiles
                  ? 'This server reports no LoRA files.'
                  : 'None in this workflow yet.',
              style: Type.body.copyWith(color: p.inkFaint),
            ),
          ),
        for (var i = 0; i < detected.loras.length; i++)
          _LoraRow(
            key: ValueKey(detected.loras[i].nodeId),
            workflows: workflows,
            library: library,
            detected: detected,
            lora: detected.loras[i],
            position: i + 1,
          ),
        if (detected.canEditLoras)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: DeskButton(
              label: 'Add LoRA',
              icon: Icons.add_rounded,
              expand: true,
              onPressed: noFiles ? null : () => _add(context),
            ),
          ),
      ],
    );
  }
}

class _LoraRow extends StatelessWidget {
  final ComfyWorkflowService workflows;
  final ModelLibrary library;
  final DetectedWorkflowSettings detected;
  final DetectedLora lora;
  final int position;

  const _LoraRow({
    super.key,
    required this.workflows,
    required this.library,
    required this.detected,
    required this.lora,
    required this.position,
  });

  /// LoRA strengths are the reason the tape exists. Most sit between 0 and
  /// 1, sliders are trained for +-10, and the node declares +-100 - so half
  /// a point per drag-step, a tenth when you lift the finger away, and a
  /// hundredth when you lift it further. The node's own bounds still cap it.
  static const _strengthSteps = [0.5, 0.1, 0.01];

  @override
  Widget build(BuildContext context) {
    // The saved file need not be one the server currently lists (a renamed
    // or moved LoRA). Dropping it from the options would leave the row
    // showing a value the browser does not contain, and the first edit
    // would silently rewrite the workflow to something else.
    final files = <String>[
      if (!detected.availableLoras.contains(lora.fileName)) lora.fileName,
      ...detected.availableLoras,
    ];
    final options = lora.strength.input.options;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModelPickerTile(
            library: library,
            kind: ManagedModelKind.lora,
            label: 'LoRA $position',
            value: lora.fileName,
            options: files,
            onChanged: (file) =>
                workflows.updateDetectedSettingValue(lora.file, file),
            // Attached to the row rather than floating above it, so there is
            // never a question about which LoRA a delete applies to.
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => workflows.removeLora(lora),
              child: const Padding(
                padding: EdgeInsets.only(left: Space.sm, right: Space.xs),
                child: Icon(Icons.delete_outline_rounded,
                    size: 18, color: DeskPalette.alert),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          DeskTape(
            label: 'Strength',
            value: lora.strengthValue,
            min: (options['min'] as num?)?.toDouble(),
            max: (options['max'] as num?)?.toDouble(),
            steps: _strengthSteps,
            format: (v) => trimNumber(v, 2),
            onChanged: (v) =>
                workflows.updateDetectedSettingValue(lora.strength, v),
          ),
        ],
      ),
    );
  }
}
