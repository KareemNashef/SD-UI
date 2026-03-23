// ==================== Inpaint Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modals/crop_modal.dart';
import 'package:sd_companion/elements/modals/resize_modal.dart';
import 'package:sd_companion/elements/modals/upscale_modal.dart';
import 'package:sd_companion/elements/ui/image_upload_container.dart';
import 'package:sd_companion/elements/widgets/glass_app_bar.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

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
        appBar: GlassAppBar(title: 'CANVAS', onTitleTap: () => setState(() => _showToolbar = !_showToolbar), subtitle: _showToolbar ? 'Tap title to hide tools' : 'Tap title for tools'),
        body: Stack(
          children: [
            const SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 110, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Focus(autofocus: true, child: SizedBox.shrink()),
                  ImageContainer(),
                ],
              ),
            ),

            // Floating Toolbar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.fastOutSlowIn,
              top: _showToolbar ? 105 : 60,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.glassBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _toolbarItem(icon: Icons.crop_rounded, label: 'Crop', onTap: () => showCropModal(context)),
          _vDivider(),
          _toolbarItem(icon: Icons.hd_rounded, label: 'Upscale', onTap: () => showUpscaleModal(context)),
          _vDivider(),
          _toolbarItem(icon: Icons.photo_size_select_large_rounded, label: 'Resize', onTap: () => showResizeModal(context)),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(height: 20, width: 1, color: Colors.white.withValues(alpha: 0.1));
  }

  Widget _toolbarItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.accentPrimary, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
