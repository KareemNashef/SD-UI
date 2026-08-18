// ==================== Inpaint Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modals/crop_modal.dart';
import 'package:sd_companion/elements/modals/resize_modal.dart';
import 'package:sd_companion/elements/modals/stitch_modal.dart';
import 'package:sd_companion/elements/modals/upscale_modal.dart';
import 'package:sd_companion/elements/ui/image_upload_container.dart';
import 'package:sd_companion/elements/widgets/context_strip.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Inpaint Page Implementation

class InpaintPage extends StatefulWidget {
  const InpaintPage({super.key});

  @override
  InpaintPageState createState() => InpaintPageState();
}

class InpaintPageState extends State<InpaintPage> with AutomaticKeepAliveClientMixin {
  bool _showToolbar = false;

  // ===== Build Methods ===== //

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            const SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 122, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Focus(autofocus: true, child: SizedBox.shrink()),
                  ImageContainer(),
                ],
              ),
            ),

            // Context strip (checkpoint/workflow quick-switch) + tools toggle,
            // pinned at the top - the one thing on this screen that's always
            // visible regardless of scroll position or toolbar state.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      const Expanded(child: ContextStrip()),
                      const SizedBox(width: 8),
                      _ToolsToggleButton(
                        active: _showToolbar,
                        onTap: () => setState(() => _showToolbar = !_showToolbar),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Floating Toolbar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.fastOutSlowIn,
              top: _showToolbar ? 70 : 30,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showToolbar ? 1.0 : 0.0,
                child: IgnorePointer(ignoring: !_showToolbar, child: _buildCanvasToolbar()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasToolbar() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.mist.withValues(alpha: 0.10), AppTheme.ink2.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: AppTheme.glassBorder),
          boxShadow: [BoxShadow(color: AppTheme.ink.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _toolbarItem(icon: Icons.crop_rounded, label: 'Crop', onTap: () => showCropModal(context)),
            _vDivider(),
            if (globalBackend.capabilities.upscale)
              _toolbarItem(icon: Icons.hd_rounded, label: 'Upscale', onTap: () => showUpscaleModal(context)),
            if (globalBackend.capabilities.upscale) _vDivider(),
            _toolbarItem(icon: Icons.photo_size_select_large_rounded, label: 'Resize', onTap: () => showResizeModal(context)),
            if (globalBackend.capabilities.stitching) _vDivider(),
            if (globalBackend.capabilities.stitching)
              _toolbarItem(icon: Icons.aspect_ratio_rounded, label: 'Stitch', onTap: () => showStitchModal(context)),
          ],
        ),
      ),
    );
  }

  Widget _vDivider() {
    return Container(height: 20, width: 1, color: AppTheme.mist18);
  }

  Widget _toolbarItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.accentPrimary, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: AppTheme.mist55, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolsToggleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _ToolsToggleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: AppTheme.durationMedium,
          curve: AppTheme.ease,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: active ? AppTheme.accentPrimary.withValues(alpha: 0.16) : AppTheme.mist.withValues(alpha: 0.07),
            shape: BoxShape.circle,
            border: Border.all(color: active ? AppTheme.accentPrimary.withValues(alpha: 0.5) : AppTheme.glassBorder),
          ),
          child: Icon(
            Icons.construction_rounded,
            size: 19,
            color: active ? AppTheme.accentPrimary : AppTheme.mist55,
          ),
        ),
      ),
    );
  }
}
