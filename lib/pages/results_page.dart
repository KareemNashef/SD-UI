// ==================== Results Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/results_carousel.dart';
import 'package:sd_companion/elements/progress_overlay.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Results Page Class ========== //

class ResultsPage extends StatefulWidget {
  // ===== Constructor ===== //
  const ResultsPage({super.key});

  @override
  ResultsPageState createState() => ResultsPageState();
}

class ResultsPageState extends State<ResultsPage> {
  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,

        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Title Text
            const Text(
              'Results',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            // Spacer
            const SizedBox(height: 8),

            // Server Status
            ValueListenableBuilder(
              valueListenable: globalServerStatus,
              builder: (context, value, child) {
                return Container(
                  width: 60,
                  height: 5,
                  decoration: BoxDecoration(
                    color: value ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(5),
                  ),
                );
              },
            ),
          ],
        ),
      ),

      // Content with Progress Overlay
      body: Stack(
        children: [
          // Main Content
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [ResultsCarousel()],
            ),
          ),

          // Progress Overlay
          ProgressOverlay(),
        ],
      ),
    );
  }
}
