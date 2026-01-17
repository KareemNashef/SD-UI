// ==================== Results Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/ui/progress_overlay.dart';
import 'package:sd_companion/elements/ui/results_carousel.dart';
import 'package:sd_companion/elements/widgets/glass_app_bar.dart';

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
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(title: 'LIBRARY'),
        body: Stack(
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
