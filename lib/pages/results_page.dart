// ==================== Results Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modals/comfy_server_library_modal.dart';
import 'package:sd_companion/elements/ui/progress_overlay.dart';
import 'package:sd_companion/elements/ui/results_carousel.dart';
import 'package:sd_companion/elements/widgets/glass_app_bar.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Results Page Implementation

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key});

  @override
  ResultsPageState createState() => ResultsPageState();
}

class ResultsPageState extends State<ResultsPage>
    with AutomaticKeepAliveClientMixin {
  // ===== Build Methods ===== //

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // REQUIRED!

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: 'LIBRARY',
          actions: [
            // Only Comfy currently has a real server-side endpoint this can
            // be built against - see BackendCapabilities.serverLibrary.
            ValueListenableBuilder(
              valueListenable: globalActiveBackendKind,
              builder: (context, kind, child) {
                if (!globalBackend.capabilities.serverLibrary) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Browse server library',
                  onPressed: () => showComfyServerLibraryModal(context),
                  icon: Icon(Icons.cloud_download_rounded, color: AppTheme.accentPrimary),
                );
              },
            ),
          ],
        ),
        body: const Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 110, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Focus(autofocus: true, child: SizedBox.shrink()),
                  ResultsCarousel(),
                ],
              ),
            ),
            ProgressOverlay(),
          ],
        ),
      ),
    );
  }
}
