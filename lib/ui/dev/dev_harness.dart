// ==================== Dev Harness ==================== //

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';
import 'package:sd_companion/ui/dev/desk_lab.dart';
import 'package:sd_companion/ui/dev/generation_lab.dart';
import 'package:sd_companion/ui/dev/state_inspector.dart';

/// A scratch screen for checking the rebuild on a real device.
///
/// It answers the two things that are easy to get wrong by looking at a phone
/// rather than by reasoning about code: does the Desk system hold together on
/// real hardware, and do the stores actually drive the UI. Not part of the
/// product - it goes once the real front page is built on the same pieces.
class DevHarness extends StatefulWidget {
  const DevHarness({super.key});

  @override
  State<DevHarness> createState() => _DevHarnessState();
}

class _DevHarnessState extends State<DevHarness> {
  int _tab = 0;
  DeskMode _mode = DeskMode.day;

  @override
  Widget build(BuildContext context) {
    return Desk(
      mode: _mode,
      child: Builder(
        builder: (context) {
          final p = DeskTheme.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: [
                  _Header(
                    mode: _mode,
                    onToggleMode: () => setState(() => _mode =
                        _mode == DeskMode.day ? DeskMode.night : DeskMode.day),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: DeskTabStrip<int>(
                      value: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                      tabs: const [
                        DeskTab(value: 0, label: 'Desk', icon: Icons.dashboard_rounded),
                        DeskTab(value: 1, label: 'Run', icon: Icons.play_arrow_rounded),
                        DeskTab(value: 2, label: 'State', icon: Icons.data_object_rounded),
                      ],
                    ),
                  ),
                  // The edge the tabs are attached to, so the active tab reads
                  // as joined to the panel below rather than floating above it.
                  Container(height: Stroke.standard, color: p.ink),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: const [
                        DeskLab(),
                        GenerationLab(),
                        StateInspector(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final DeskMode mode;
  final VoidCallback onToggleMode;

  const _Header({required this.mode, required this.onToggleMode});

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, Space.md, Space.gutter, Space.md),
      child: Row(
        children: [
          Text('Aperture', style: Type.deskTitle.copyWith(color: p.ink)),
          const SizedBox(width: Space.sm),
          const DeskCard(label: 'desk'),
          const Spacer(),
          DeskCard(
            label: mode == DeskMode.day ? 'day' : 'night',
            accent: true,
            onTap: onToggleMode,
          ),
        ],
      ),
    );
  }
}
