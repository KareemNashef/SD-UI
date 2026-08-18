// ==================== Comfy Workflow Settings ==================== //
//
// ComfyUI's equivalent of CheckpointSettings: import/select/manage saved
// workflows and edit their auto-detected settings. Prompt/negative-prompt/
// input-image are bound to the existing canvas and shown here only as a
// read-only summary; everything else the detector found (model/CLIP/VAE
// loaders, sampler params, latent size) is editable, styled the same way
// CheckpointSettings styles Forge's sampler/scheduler tiles and sliders.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:sd_companion/elements/modals/generic_option_select_modal.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_slider.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/logic/comfy/comfy_node_schema.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_type.dart';
import 'package:sd_companion/logic/comfy/workflow_auto_detector.dart';

const Map<String, String> _kFriendlyLabels = {
  'unet_name': 'Model',
  'model_name': 'Model',
  'model_path': 'Model',
  'ckpt_name': 'Checkpoint',
  'clip_name': 'CLIP Loader',
  'type': 'CLIP Type',
  'vae_name': 'VAE',
  'seed': 'Seed',
  'steps': 'Steps',
  'cfg': 'CFG Scale',
  'sampler_name': 'Sampler',
  'scheduler': 'Scheduler',
  'denoise': 'Denoise',
  'width': 'Width',
  'height': 'Height',
  'batch_size': 'Batch Size',
  'aspect_ratio': 'Aspect Ratio',
  'megapixels': 'Megapixels',
  'multiple': 'Multiple Of',
  'weight_dtype': 'Precision',
  'cpu_offload': 'CPU Offload',
};

String _friendlyLabel(String widgetName) {
  final known = _kFriendlyLabels[widgetName];
  if (known != null) return known;
  return widgetName
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// A numeric range is only slider-friendly when it's actually bounded to a
/// sane size - ComfyUI reports seed's range as [0, 2^64), which would make
/// a useless slider; those fall back to a plain number field instead.
bool _isSliderFriendly(ComfyInputSpec input) {
  final min = (input.options['min'] as num?)?.toDouble();
  final max = (input.options['max'] as num?)?.toDouble();
  if (min == null || max == null) return false;
  return (max - min) <= 10000 && max < 1000000;
}

class ComfyWorkflowSettings extends StatefulWidget {
  const ComfyWorkflowSettings({super.key});

  @override
  State<ComfyWorkflowSettings> createState() => _ComfyWorkflowSettingsState();
}

class _ComfyWorkflowSettingsState extends State<ComfyWorkflowSettings> {
  bool _importing = false;

  // Live drag feedback for in-flight slider edits, keyed by "nodeId:widgetName".
  // GlassSlider is stateless, so without this the thumb would snap back to
  // the last-persisted value on every frame instead of following the drag.
  final Map<String, double> _sliderDragValues = {};

  // ===== Import / workflow management (unchanged behavior) ===== //

  Future<void> _importWorkflow() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _showError('Could not read the selected file');
        return;
      }
      if (!mounted) return;
      final type = await _pickWorkflowType();
      if (type == null) return; // cancelled

      final text = String.fromCharCodes(bytes);
      final name = file.name.replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
      await ComfyWorkflowService.instance.importWorkflow(text, name: name, workflowType: type);
    } on ComfyWorkflowParseException catch (e) {
      _showError('Invalid workflow: ${e.message}');
    } catch (e) {
      _showError('Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<ComfyWorkflowType?> _pickWorkflowType({ComfyWorkflowType? initial}) {
    return showDialog<ComfyWorkflowType>(
      context: context,
      builder: (ctx) => _WorkflowTypeDialog(initial: initial),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  void _showWorkflowActions(ComfyWorkflowRecord record) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.glassBackground.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline, color: Colors.white70),
                title: const Text('Rename', style: TextStyle(color: AppTheme.mist)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _renameWorkflow(record);
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded, color: Colors.white70),
                title: const Text('Change type', style: TextStyle(color: AppTheme.mist)),
                subtitle: Text(record.workflowType.displayName, style: const TextStyle(color: Colors.white38)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final type = await _pickWorkflowType(initial: record.workflowType);
                  if (type != null) {
                    await ComfyWorkflowService.instance.setWorkflowType(record.id, type);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: Colors.white70),
                title: const Text('Duplicate', style: TextStyle(color: AppTheme.mist)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await ComfyWorkflowService.instance.duplicateWorkflow(record.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.error),
                title: const Text('Delete', style: TextStyle(color: AppTheme.error)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await ComfyWorkflowService.instance.deleteWorkflow(record.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameWorkflow(ComfyWorkflowRecord record) async {
    final controller = TextEditingController(text: record.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text('Rename workflow', style: TextStyle(color: AppTheme.mist)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.mist),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      await ComfyWorkflowService.instance.renameWorkflow(record.id, newName);
    }
  }

  // ===== Header / workflow list ===== //

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.comfyAccentPrimary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.comfyAccentPrimary.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.hub_rounded, color: AppTheme.comfyAccentPrimary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'COMFYUI',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white54, letterSpacing: 1.5),
              ),
              const SizedBox(height: 2),
              Text(
                'Workflows',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.mist.withValues(alpha: 0.95)),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _importing ? null : _importWorkflow,
          icon: _importing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file_rounded, color: AppTheme.comfyAccentPrimary),
          tooltip: 'Import workflow JSON',
        ),
      ],
    );
  }

  /// A single dropdown tile showing the active workflow, mirroring
  /// CheckpointSettings' Sampler/Scheduler tiles - tapping it opens a picker
  /// instead of listing every saved workflow inline, which used to eat a lot
  /// of vertical space once more than a couple were imported.
  Widget _buildWorkflowSelector(List<ComfyWorkflowRecord> workflows, ComfyWorkflowRecord? active) {
    if (workflows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.mist.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.mist.withValues(alpha: 0.08)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white38, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No workflows imported yet. Import the editor JSON exported from ComfyUI.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _openWorkflowPicker(workflows, active?.id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.mist.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.mist.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(Icons.account_tree_rounded, color: AppTheme.comfyAccentSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE WORKFLOW',
                    style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active?.name ?? 'Select a workflow',
                    style: const TextStyle(color: AppTheme.mist, fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (active != null)
                    Text(
                      '${active.workflowType.displayName} · ${workflows.length} saved',
                      style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.35), fontSize: 11),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  void _openWorkflowPicker(List<ComfyWorkflowRecord> workflows, String? activeId) {
    GlassModal.show(
      context,
      heightFactor: 0.75,
      child: _WorkflowPickerModal(
        workflows: workflows,
        activeId: activeId,
        itemBuilder: _buildWorkflowListItem,
      ),
    );
  }

  Widget _buildWorkflowListItem(ComfyWorkflowRecord record, String? activeId) {
    final isActive = record.id == activeId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive ? AppTheme.comfyAccentPrimary.withValues(alpha: 0.12) : AppTheme.mist.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            ComfyWorkflowService.instance.selectWorkflow(record.id);
            Navigator.pop(context);
          },
          onLongPress: () => _showWorkflowActions(record),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isActive ? AppTheme.comfyAccentPrimary : Colors.white24,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.name,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        record.workflowType.displayName,
                        style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.35), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
                  onPressed: () => _showWorkflowActions(record),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== Workflow Settings (Forge-styled controls) ===== //

  Widget _buildSettingsGroup(String title, IconData icon, List<DetectedWidget> widgets) {
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.comfyAccentSecondary, size: 14),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final w in widgets) ...[_buildSettingControl(w), const SizedBox(height: 12)],
        ],
      ),
    );
  }

  Widget _buildSettingControl(DetectedWidget widget) {
    if (widget.isLinked) return _buildLinkedRow(widget);
    if (widget.controlAfterGenerateSlotIndex != null) return _buildSeedRow(widget);

    final input = widget.input;
    if (input.type == 'COMBO' && input.comboOptions != null) {
      return _buildOptionTile(widget);
    }
    if (input.type == 'BOOLEAN') {
      return _buildBooleanToggle(widget);
    }
    if ((input.type == 'INT' || input.type == 'FLOAT') && _isSliderFriendly(input)) {
      return _buildNumberSlider(widget);
    }
    if (input.type == 'INT' || input.type == 'FLOAT') {
      return _buildNumberField(widget);
    }
    return _buildTextField(widget);
  }

  /// Mirrors CheckpointSettings' sampler/scheduler tiles: icon + small-caps
  /// label + bold value + chevron, opening a picker on tap.
  Widget _buildOptionTile(DetectedWidget widget) {
    final options = widget.input.comboOptions!.map((e) => e.toString()).toList();
    final current = options.contains(widget.currentValue?.toString()) ? widget.currentValue.toString() : options.first;

    return InkWell(
      onTap: () => showGenericOptionSelectModal(
        context: context,
        title: _friendlyLabel(widget.input.name),
        subtitle: widget.label,
        options: options,
        current: current,
        accentColor: AppTheme.comfyAccentPrimary,
        onSelect: (value) => ComfyWorkflowService.instance.updateDetectedSettingValue(widget, value),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.mist.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.mist.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, color: AppTheme.comfyAccentSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _friendlyLabel(widget.input.name).toUpperCase(),
                    style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    current,
                    style: const TextStyle(color: AppTheme.mist, fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  /// Mirrors CheckpointSettings' Denoising Strength/Steps/CFG sliders,
  /// using the real min/max/step ComfyUI reports for this widget.
  Widget _buildNumberSlider(DetectedWidget widget) {
    final input = widget.input;
    final min = (input.options['min'] as num?)?.toDouble() ?? 0;
    final max = (input.options['max'] as num?)?.toDouble() ?? 100;
    final isInt = input.type == 'INT';
    final step = (input.options['step'] as num?)?.toDouble();
    final divisions = step != null && step > 0 ? ((max - min) / step).round().clamp(1, 1000) : null;
    final key = '${widget.node.id}:${input.name}';
    final baseValue = ((widget.currentValue as num?) ?? min).toDouble().clamp(min, max);
    final value = (_sliderDragValues[key] ?? baseValue).clamp(min, max);

    return GlassSlider(
      label: _friendlyLabel(input.name),
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      accentColor: AppTheme.comfyAccentSecondary,
      valueFormatter: (v) => isInt ? v.toInt().toString() : v.toStringAsFixed(2),
      onChanged: (v) => setState(() => _sliderDragValues[key] = v),
      onChangeEnd: (v) {
        _sliderDragValues.remove(key);
        ComfyWorkflowService.instance.updateDetectedSettingValue(
          widget,
          isInt ? v.round() : double.parse(v.toStringAsFixed(3)),
        );
      },
    );
  }

  Widget _buildNumberField(DetectedWidget widget) {
    return _labeledRow(
      _friendlyLabel(widget.input.name),
      SizedBox(
        width: 140,
        child: _commitOnBlurField(
          initialText: widget.currentValue?.toString() ?? '',
          keyboardType: TextInputType.numberWithOptions(decimal: widget.input.type == 'FLOAT'),
          onCommit: (text) {
            final parsed = widget.input.type == 'INT' ? int.tryParse(text) : double.tryParse(text);
            if (parsed != null) {
              ComfyWorkflowService.instance.updateDetectedSettingValue(widget, parsed);
            }
          },
        ),
      ),
    );
  }

  Widget _buildTextField(DetectedWidget widget) {
    return _labeledRow(
      _friendlyLabel(widget.input.name),
      _commitOnBlurField(
        initialText: widget.currentValue?.toString() ?? '',
        onCommit: (text) => ComfyWorkflowService.instance.updateDetectedSettingValue(widget, text),
      ),
    );
  }

  /// A GlassInput that commits [onCommit] when the field loses focus
  /// (keyboard "done" or tapping away both blur it) instead of on every
  /// keystroke - `GlassInput` only exposes `onChanged`, and committing (and
  /// thus re-running the detector) per keystroke would rebuild the
  /// controller mid-edit and throw the cursor to the end of the field.
  Widget _commitOnBlurField({
    required String initialText,
    TextInputType? keyboardType,
    bool enabled = true,
    required ValueChanged<String> onCommit,
  }) {
    final controller = TextEditingController(text: initialText);
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) onCommit(controller.text);
    });
    return GlassInput(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      maxLines: 1,
      enabled: enabled,
      accentColor: AppTheme.comfyAccentPrimary,
    );
  }

  Widget _labeledRow(String label, Widget control) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: control),
      ],
    );
  }

  /// Mirrors CheckpointSettings' Inpaint/Full-image mode pair.
  Widget _buildBooleanToggle(DetectedWidget widget) {
    final isOn = widget.currentValue == true;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            _friendlyLabel(widget.input.name),
            style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(
                child: _togglePairButton(
                  label: 'On',
                  icon: Icons.check_rounded,
                  selected: isOn,
                  onTap: () => ComfyWorkflowService.instance.updateDetectedSettingValue(widget, true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _togglePairButton(
                  label: 'Off',
                  icon: Icons.close_rounded,
                  selected: !isOn,
                  onTap: () => ComfyWorkflowService.instance.updateDetectedSettingValue(widget, false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Seed gets its own row: a number field paired with the Fixed/Random
  /// toggle ComfyUI's `control_after_generate` represents.
  Widget _buildSeedRow(DetectedWidget widget) {
    final random = widget.isRandomized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _friendlyLabel(widget.input.name),
          style: TextStyle(color: AppTheme.mist.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _commitOnBlurField(
                initialText: widget.currentValue?.toString() ?? '',
                keyboardType: TextInputType.number,
                enabled: !random,
                onCommit: (text) {
                  final parsed = int.tryParse(text);
                  if (parsed != null) {
                    ComfyWorkflowService.instance.updateDetectedSettingValue(widget, parsed);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _togglePairButton(
                label: random ? 'Random' : 'Fixed',
                icon: random ? Icons.casino_rounded : Icons.lock_outline_rounded,
                selected: random,
                onTap: () => ComfyWorkflowService.instance.updateSeedRandomFlag(widget, !random),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Shared visual for the two-button toggle pattern (mirrors
  /// CheckpointSettings' _buildImg2ImgModeButton).
  Widget _togglePairButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppTheme.comfyAccentPrimary.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.comfyAccentPrimary.withValues(alpha: 0.5) : AppTheme.mist.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? AppTheme.comfyAccentPrimary : Colors.white54),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: selected ? Colors.white : Colors.white60, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedRow(DetectedWidget widget) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.mist.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.mist.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: Colors.white24, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_friendlyLabel(widget.input.name)} - linked to another node',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      backgroundColor: AppTheme.surfaceCard,
      borderColor: AppTheme.glassBorder,
      borderRadius: AppTheme.radiusLarge,
      padding: const EdgeInsets.all(24.0),
      child: ValueListenableBuilder<List<ComfyWorkflowRecord>>(
        valueListenable: ComfyWorkflowService.instance.workflows,
        builder: (context, workflows, child) {
          return ValueListenableBuilder<String?>(
            valueListenable: ComfyWorkflowService.instance.activeWorkflowId,
            builder: (context, activeId, child) {
              ComfyWorkflowRecord? active;
              for (final w in workflows) {
                if (w.id == activeId) {
                  active = w;
                  break;
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildWorkflowSelector(workflows, active),
                  if (activeId != null)
                    ValueListenableBuilder<DetectedWorkflowSettings?>(
                      valueListenable: ComfyWorkflowService.instance.activeDetected,
                      builder: (context, detected, child) {
                        if (detected == null) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            _buildSettingsGroup('Diffusion Model', Icons.memory_rounded, detected.modelSettings),
                            _buildSettingsGroup('CLIP', Icons.text_fields_rounded, detected.clipSettings),
                            _buildSettingsGroup('VAE', Icons.image_outlined, detected.vaeSettings),
                            _buildSettingsGroup('Sampler', Icons.waves_rounded, detected.samplerSettings),
                            _buildSettingsGroup('Latent', Icons.aspect_ratio_rounded, detected.latentSettings),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _WorkflowTypeDialog extends StatefulWidget {
  final ComfyWorkflowType? initial;
  const _WorkflowTypeDialog({this.initial});

  @override
  State<_WorkflowTypeDialog> createState() => _WorkflowTypeDialogState();
}

class _WorkflowTypeDialogState extends State<_WorkflowTypeDialog> {
  late ComfyWorkflowType _selected = widget.initial ?? ComfyWorkflowType.imageToImage;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceCard,
      title: const Text('Workflow type', style: TextStyle(color: AppTheme.mist)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This decides how the main page presents the workflow (image upload, mask painting, etc).',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          for (final type in ComfyWorkflowType.values)
            RadioListTile<ComfyWorkflowType>(
              value: type,
              groupValue: _selected,
              activeColor: AppTheme.comfyAccentPrimary,
              onChanged: (value) => setState(() => _selected = value!),
              title: Text(type.displayName, style: const TextStyle(color: AppTheme.mist)),
              subtitle: Text(type.description, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.comfyAccentPrimary),
          child: const Text('Continue', style: TextStyle(color: AppTheme.mist)),
        ),
      ],
    );
  }
}

/// The picker sheet opened by the workflow dropdown tile - same shape as
/// GenericOptionSelectModal (header + optional search + list), but over
/// ComfyWorkflowRecord instead of plain strings so each row can carry a
/// type subtitle and a "more" action button.
class _WorkflowPickerModal extends StatefulWidget {
  final List<ComfyWorkflowRecord> workflows;
  final String? activeId;
  final Widget Function(ComfyWorkflowRecord record, String? activeId) itemBuilder;

  const _WorkflowPickerModal({
    required this.workflows,
    required this.activeId,
    required this.itemBuilder,
  });

  @override
  State<_WorkflowPickerModal> createState() => _WorkflowPickerModalState();
}

class _WorkflowPickerModalState extends State<_WorkflowPickerModal> {
  final TextEditingController _searchController = TextEditingController();
  late List<ComfyWorkflowRecord> _filtered = widget.workflows;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.workflows
          : widget.workflows.where((w) => w.name.toLowerCase().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassHeader(
          title: 'Workflows',
          subtitle: '${widget.workflows.length} saved',
          iconColor: AppTheme.comfyAccentPrimary,
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        if (widget.workflows.length > 8)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GlassInput(
              controller: _searchController,
              hintText: 'Search...',
              prefixIcon: Icons.search,
              maxLines: 1,
              accentColor: AppTheme.comfyAccentPrimary,
            ),
          ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: _filtered.length,
            itemBuilder: (context, index) => widget.itemBuilder(_filtered[index], widget.activeId),
          ),
        ),
      ],
    );
  }
}
