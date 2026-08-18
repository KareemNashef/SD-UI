// ==================== Quick Switch Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_type.dart';

// Quick Switch Modal Implementation
//
// The fast path from Create's context strip: pick a workflow and go, no
// rename/duplicate/delete clutter (that's what the full picker in Settings
// is for - see comfy_workflow_settings.dart).
void showQuickSwitchModal(BuildContext context) {
  GlassModal.show(context, heightFactor: 0.6, child: const _QuickSwitchSheet());
}

class _QuickSwitchSheet extends StatelessWidget {
  const _QuickSwitchSheet();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ComfyWorkflowRecord>>(
      valueListenable: ComfyWorkflowService.instance.workflows,
      builder: (context, workflows, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: ComfyWorkflowService.instance.activeWorkflowId,
          builder: (context, activeId, __) {
            return Column(
              children: [
                GlassHeader(
                  title: 'Switch Workflow',
                  subtitle: '${workflows.length} saved',
                  icon: Icons.hub_rounded,
                  iconColor: AppTheme.accentPrimary,
                  trailing: IconButton(
                    icon: Icon(Icons.close, color: AppTheme.mist55),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: workflows.isEmpty
                      ? Center(
                          child: Text(
                            'No workflows imported yet.\nAdd one from Settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.mist35, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          physics: const BouncingScrollPhysics(),
                          itemCount: workflows.length,
                          itemBuilder: (context, index) {
                            final record = workflows[index];
                            final isActive = record.id == activeId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: isActive ? AppTheme.accentPrimary.withValues(alpha: 0.14) : AppTheme.mist.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                                  onTap: () {
                                    ComfyWorkflowService.instance.selectWorkflow(record.id);
                                    Navigator.pop(context);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isActive ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                          color: isActive ? AppTheme.accentPrimary : AppTheme.mist35,
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
                                                  color: isActive ? AppTheme.mist : AppTheme.mist80,
                                                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                record.workflowType.displayName,
                                                style: TextStyle(color: AppTheme.mist35, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
