// ==================== Context Strip ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modals/checkpoint_select_modal.dart';
import 'package:sd_companion/elements/modals/quick_switch_modal.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_type.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

// Context Strip Implementation
//
// The persistent "what am I generating with" affordance at the top of
// Create - tapping it opens a quick-switch sheet in place, without ever
// leaving the canvas. This is the single highest-frequency piece of state
// after the prompt itself, so it gets its own always-visible surface
// instead of living a tab away inside Settings.
class ContextStrip extends StatefulWidget {
  const ContextStrip({super.key});

  @override
  State<ContextStrip> createState() => _ContextStripState();
}

class _ContextStripState extends State<ContextStrip> {
  bool _isSwitchingCheckpoint = false;

  @override
  void initState() {
    super.initState();
    globalActiveBackendKind.addListener(_onChanged);
  }

  @override
  void dispose() {
    globalActiveBackendKind.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openForgeSwitch() async {
    showCheckpointSelectModal(
      context: context,
      onSelect: (modelName) async {
        final oldData = globalCheckpointDataMap[globalCurrentCheckpointName];
        final newData = globalCheckpointDataMap[modelName];
        Navigator.pop(context);
        setState(() => _isSwitchingCheckpoint = true);

        if (oldData?.baseModel != newData?.baseModel) {
          globalSelectedLoras.value = {};
          globalSelectedLoraTags.value = {};
        }
        globalCurrentCheckpointName = modelName;
        _applyModelDefaults(modelName);
        await setCheckpoint();

        if (mounted) setState(() => _isSwitchingCheckpoint = false);
      },
    );
  }

  void _applyModelDefaults(String modelName) {
    final data = globalCheckpointDataMap[modelName];
    if (data == null) return;
    globalCurrentSamplingSteps = data.samplingSteps;
    globalCurrentSamplingMethod = data.samplingMethod;
    globalCurrentScheduler = data.scheduler;
    globalCurrentCfgScale = data.cfgScale;
    globalDenoiseStrength = data.denoisingStrength;
    globalCurrentResolutionWidth = data.resolutionWidth;
    globalCurrentResolutionHeight = data.resolutionHeight;
    StorageService.saveCheckpointDataMap();
  }

  @override
  Widget build(BuildContext context) {
    final isComfy = globalActiveBackendKind.value == BackendKind.comfy;
    return isComfy ? _buildComfyStrip() : _buildForgeStrip();
  }

  Widget _buildForgeStrip() {
    final data = globalCheckpointDataMap[globalCurrentCheckpointName];
    return _StripShell(
      onTap: _isSwitchingCheckpoint ? null : _openForgeSwitch,
      loading: _isSwitchingCheckpoint,
      title: globalCurrentCheckpointName.isEmpty ? 'Select a checkpoint' : globalCurrentCheckpointName,
      subtitle: 'Forge Neo${data?.baseModel != null ? ' · ${data!.baseModel}' : ''}',
    );
  }

  Widget _buildComfyStrip() {
    return ValueListenableBuilder(
      valueListenable: ComfyWorkflowService.instance.workflows,
      builder: (context, workflows, _) {
        return ValueListenableBuilder(
          valueListenable: ComfyWorkflowService.instance.activeWorkflowId,
          builder: (context, activeId, __) {
            ComfyWorkflowRecord? active;
            for (final w in workflows) {
              if (w.id == activeId) {
                active = w;
                break;
              }
            }
            return _StripShell(
              onTap: () => showQuickSwitchModal(context),
              loading: false,
              title: active?.name ?? 'Select a workflow',
              subtitle: active != null ? 'ComfyUI · ${active.workflowType.displayName}' : 'ComfyUI',
            );
          },
        );
      },
    );
  }
}

class _StripShell extends StatelessWidget {
  final VoidCallback? onTap;
  final bool loading;
  final String title;
  final String subtitle;

  const _StripShell({required this.onTap, required this.loading, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentPrimary;
    return GlassStrip(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.7), blurRadius: 8, spreadRadius: 1)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.mist, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.mist55, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
          else
            Icon(Icons.unfold_more_rounded, size: 16, color: AppTheme.mist35),
        ],
      ),
    );
  }
}

/// A thin, always-visible glass pill - the shared shell behind the context
/// strip. Kept separate/public in case other persistent single-line glass
/// affordances want the same shape later.
class GlassStrip extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const GlassStrip({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.mist.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}
