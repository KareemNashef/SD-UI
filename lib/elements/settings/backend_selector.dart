// ==================== Backend Selector ==================== //
//
// Lets the user pick Forge Neo or ComfyUI as the active backend. Switching
// clears the previous backend's connection status (so a stale "connected"
// badge never survives a switch) and reloads the appropriate profile data.

import 'package:flutter/material.dart';

import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/backend_manager.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/startup/backend_startup.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

class BackendSelector extends StatefulWidget {
  const BackendSelector({super.key});

  @override
  State<BackendSelector> createState() => _BackendSelectorState();
}

class _BackendSelectorState extends State<BackendSelector> {
  bool _switching = false;

  Future<void> _select(BackendKind kind) async {
    if (_switching || globalActiveBackendKind.value == kind) return;
    setState(() => _switching = true);
    try {
      await BackendManager.instance.switchTo(kind);
      await StorageService.saveActiveBackendKind(kind);
      globalServerStatus.value = false;
      await loadActiveBackendProfile();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackendKind>(
      valueListenable: globalActiveBackendKind,
      builder: (context, active, child) {
        return GlassContainer(
          backgroundColor: AppTheme.surfaceCard,
          borderColor: AppTheme.glassBorder,
          borderRadius: AppTheme.radiusLarge,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ACTIVE BACKEND',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white54,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _BackendOption(
                      kind: BackendKind.forge,
                      isActive: active == BackendKind.forge,
                      isBusy: _switching,
                      icon: Icons.dns_rounded,
                      onTap: () => _select(BackendKind.forge),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BackendOption(
                      kind: BackendKind.comfy,
                      isActive: active == BackendKind.comfy,
                      isBusy: _switching,
                      icon: Icons.hub_rounded,
                      onTap: () => _select(BackendKind.comfy),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BackendOption extends StatelessWidget {
  final BackendKind kind;
  final bool isActive;
  final bool isBusy;
  final IconData icon;
  final VoidCallback onTap;

  const _BackendOption({
    required this.kind,
    required this.isActive,
    required this.isBusy,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentFor(kind);
    return Material(
      color: isActive ? accent.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isActive ? accent : Colors.white38, size: 26),
              const SizedBox(height: 8),
              Text(
                kind.displayName,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (isActive) ...[
                const SizedBox(height: 4),
                Text(
                  'ACTIVE',
                  style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small persistent badge for surfaces that just need to show which backend
/// is active (e.g. the connection card, progress overlay) without offering
/// to switch.
class BackendIdentityBadge extends StatelessWidget {
  final bool compact;
  const BackendIdentityBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackendKind>(
      valueListenable: globalActiveBackendKind,
      builder: (context, kind, child) {
        final accent = AppTheme.accentFor(kind);
        return Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                kind == BackendKind.comfy ? Icons.hub_rounded : Icons.dns_rounded,
                color: accent,
                size: compact ? 12 : 14,
              ),
              SizedBox(width: compact ? 4 : 6),
              Text(
                kind.displayName,
                style: TextStyle(
                  color: accent,
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
