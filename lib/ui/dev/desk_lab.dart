// ==================== Desk Lab ==================== //

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// Every component in DESIGN.md on one screen, so the system can be checked
/// on real hardware rather than reasoned about.
///
/// What to look for:
///  * pressing anything sinks it into its own shadow and springs back;
///  * shadows are hard-edged ink offsets, never blurred;
///  * paper content has square corners and controls have rounded ones;
///  * the sheet's outpaint handles pulse, and nothing else moves on its own.
class DeskLab extends StatefulWidget {
  const DeskLab({super.key});

  @override
  State<DeskLab> createState() => _DeskLabState();
}

class _DeskLabState extends State<DeskLab> {
  double _denoise = 0.62;
  double _steps = 28;
  bool _randomSeed = true;
  bool _hires = false;
  String _sampler = 'euler';
  String _mode = 'inpaint';
  int _tool = 0;
  String _selectedPrint = 'run_b';

  static const _demoPrints = [
    ('run_a', [Color(0xFFFFE2A8), Color(0xFF241030)]),
    ('run_b', [Color(0xFF7FE3C6), Color(0xFF1D5148)]),
    ('run_c', [Color(0xFFF0C46A), Color(0xFF6E4A18)]),
    ('run_d', [Color(0xFF8FB4E8), Color(0xFF233B63)]),
  ];

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 110),
      children: [
        // ===== The sheet ===== //
        _Section(
          title: 'MOUNTED SHEET',
          note: 'Corner handles pulse — the only permanent animation.',
          child: SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DeskToolTray(
                  tools: const [
                    DeskTool(icon: Icons.brush_rounded, name: 'Brush'),
                    DeskTool(icon: Icons.crop_rounded, name: 'Crop'),
                    DeskTool(icon: Icons.open_in_full_rounded, name: 'Outpaint'),
                    DeskTool(icon: Icons.auto_awesome_rounded, name: 'Upscale'),
                    DeskTool(icon: Icons.download_rounded, name: 'Save'),
                  ],
                  activeIndex: _tool,
                  onSelect: (i) => setState(() => _tool = i),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: MountedSheet(
                    image: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF9A9384), Color(0xFF2E2A22)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ===== Prints ===== //
        _Section(
          title: 'PRINT SHELF',
          note: 'Drag through the deck — the nearest print rises to meet '
              'your finger, then snaps to centre on release.',
          child: PrintShelf(

            selectedId: _selectedPrint,
            onSelect: (id) => setState(() => _selectedPrint = id),
            entries: [
              for (final entry in _demoPrints)
                PrintEntry(
                  id: entry.$1,
                  image: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: entry.$2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ===== Buttons ===== //
        _Section(
          title: 'BUTTONS',
          note: 'Press and hold — the button travels into its own shadow.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DeskButton(
                      label: 'Generate',
                      icon: Icons.play_arrow_rounded,
                      kind: DeskButtonKind.primary,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: DeskButton(
                      label: 'Cancel',
                      kind: DeskButtonKind.secondary,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(
                    child: DeskButton(
                      label: 'Ghost',
                      kind: DeskButtonKind.ghost,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: DeskButton(
                      label: 'Delete',
                      kind: DeskButtonKind.destructive,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  const Expanded(child: DeskButton(label: 'Off', expand: true)),
                ],
              ),
            ],
          ),
        ),

        // ===== Chips ===== //
        _Section(
          title: 'VALUE CHIPS',
          note: 'Micro unit above, large value below.',
          child: Row(
            children: [
              DeskChip(unit: 'denoise', value: _denoise.toStringAsFixed(2), onTap: () {}),
              const SizedBox(width: Space.sm),
              DeskChip(unit: 'steps', value: _steps.round().toString(), onTap: () {}),
              const SizedBox(width: Space.sm),
              const DeskChip(unit: 'batch', value: '4'),
            ],
          ),
        ),

        // ===== Rulers ===== //
        _Section(
          title: 'RULERS',
          note: 'The thumb is a brass tab that lifts while you drag it.',
          child: DeskPanel(
            child: Column(
              children: [
                DeskRuler(
                  label: 'Denoise',
                  value: _denoise,
                  min: 0,
                  max: 1,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _denoise = v),
                ),
                const SizedBox(height: Space.lg),
                DeskRuler(
                  label: 'Steps',
                  value: _steps,
                  min: 1,
                  max: 60,
                  divisions: 59,
                  format: (v) => v.round().toString(),
                  onChanged: (v) => setState(() => _steps = v),
                ),
              ],
            ),
          ),
        ),

        // ===== Field, dropdown ===== //
        _Section(
          title: 'FIELD & DROPDOWN',
          note: 'Labels sit outside the field. The menu is an index card.',
          child: Column(
            children: [
              DeskField(
                label: 'Prompt',
                controller: TextEditingController(
                    text: 'portrait, hard side light, 35mm'),
                maxLines: 2,
              ),
              const SizedBox(height: Space.md),
              DeskDropdown<String>(
                label: 'Sampler',
                value: _sampler,
                options: const [
                  DeskOption(value: 'euler', label: 'Euler', detail: 'DEFAULT'),
                  DeskOption(value: 'euler_a', label: 'Euler Ancestral'),
                  DeskOption(value: 'dpmpp_2m', label: 'DPM++ 2M'),
                  DeskOption(value: 'ddim', label: 'DDIM'),
                ],
                onChanged: (v) => setState(() => _sampler = v),
              ),
            ],
          ),
        ),

        // ===== Tabs & toggles ===== //
        _Section(
          title: 'TABS & TOGGLES',
          note: 'Folder tabs sit flush on the panel they label.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeskTabStrip<String>(
                value: _mode,
                onChanged: (v) => setState(() => _mode = v),
                tabs: const [
                  DeskTab(value: 'text', label: 'Text', icon: Icons.title_rounded),
                  DeskTab(value: 'image', label: 'Image', icon: Icons.image_rounded),
                  DeskTab(value: 'inpaint', label: 'Inpaint', icon: Icons.brush_rounded),
                ],
              ),
              DeskPanel(
                child: Column(
                  children: [
                    _ToggleRow(
                      label: 'Random seed',
                      value: _randomSeed,
                      onChanged: (v) => setState(() => _randomSeed = v),
                    ),
                    const SizedBox(height: Space.md),
                    _ToggleRow(
                      label: 'Hires fix',
                      value: _hires,
                      onChanged: (v) => setState(() => _hires = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ===== Progress & stamps ===== //
        _Section(
          title: 'PROGRESS & STAMPS',
          note: 'Progress reuses the ruler. Stamps are outline-only.',
          child: DeskPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DeskProgress(fraction: _steps / 60, caption: 'SAMPLING'),
                const SizedBox(height: Space.md),
                const DeskProgress(caption: 'QUEUED — INDETERMINATE'),
                const SizedBox(height: Space.lg),
                const Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    DeskStamp(label: 'connected', color: DeskPalette.good),
                    DeskStamp(label: 'queued', color: DeskPalette.caution),
                    DeskStamp(label: 'unreachable', color: DeskPalette.alert),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ===== Overlays ===== //
        _Section(
          title: 'DRAWER & STICKY',
          note: 'Modals rise from the bottom edge behind a flat scrim.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeskButton(
                label: 'Open a drawer',
                icon: Icons.expand_less_rounded,
                expand: true,
                onPressed: () => showDeskDrawer<void>(
                  context: context,
                  title: 'Generation settings',
                  action: const DeskStamp(label: 'comfy', color: DeskPalette.good),
                  builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DeskRuler(
                        label: 'Guidance',
                        value: 4.5,
                        min: 1,
                        max: 15,
                        format: (v) => v.toStringAsFixed(1),
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: Space.lg),
                      Row(
                        children: [
                          const DeskChip(unit: 'width', value: '768'),
                          const SizedBox(width: Space.sm),
                          const DeskChip(unit: 'height', value: '768'),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      DeskButton(
                        label: 'Apply',
                        kind: DeskButtonKind.primary,
                        expand: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: StickyNote(
                  message: 'Saved to Downloads',
                  onDismiss: () {},
                ),
              ),
              const SizedBox(height: Space.md),
              const Align(
                alignment: Alignment.centerLeft,
                child: StickyNote(
                  message: 'ComfyUI did not answer',
                  isError: true,
                ),
              ),
            ],
          ),
        ),

        // ===== Type ===== //
        _Section(
          title: 'TYPE',
          note: 'Geist for people, Geist Mono for anything a machine produced.',
          child: DeskPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aperture', style: Type.deskTitle.copyWith(color: p.ink)),
                const SizedBox(height: Space.xs),
                Text('Generation settings',
                    style: Type.sheetTitle.copyWith(color: p.ink)),
                const SizedBox(height: Space.sm),
                Text(
                  'Body text sits at 13.5 with generous leading, because the '
                  'prompt is the thing people read most.',
                  style: Type.body.copyWith(color: p.inkMuted),
                ),
                const SizedBox(height: Space.md),
                Text('LABEL · MICRO · UPPERCASE',
                    style: Type.micro.copyWith(color: p.inkFaint)),
                const SizedBox(height: Space.xs),
                Text('0123456789 · 28 steps · 4.50 cfg',
                    style: Type.readout.copyWith(color: p.ink)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String note;
  final Widget child;

  const _Section({required this.title, required this.note, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Type.micro.copyWith(color: p.inkMuted)),
          const SizedBox(height: 2),
          Text(note,
              style: Type.body.copyWith(fontSize: 12, color: p.inkFaint)),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: Type.label.copyWith(color: p.ink))),
        DeskToggle(value: value, onChanged: onChanged),
      ],
    );
  }
}
