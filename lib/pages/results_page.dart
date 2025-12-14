// ==================== Results Page ==================== //

// Flutter imports
import 'dart:ui'; // For BackdropFilter
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
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              toolbarHeight: 70,
              centerTitle: true,
              backgroundColor: Colors.grey.shade900.withValues(alpha: 0.7),
              elevation: 0,

              title: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'GENERATION RESULTS',
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold, 
                      letterSpacing: 2.0,
                      color: Colors.white
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Neon Status Bar
                  ValueListenableBuilder(
                    valueListenable: globalServerStatus,
                    builder: (context, value, child) {
                      bool isOnline = false;
                      if (value is bool) isOnline = value;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 80,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.greenAccent : Colors.redAccent,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: isOnline 
                                ? Colors.green.withValues(alpha: 0.8) 
                                : Colors.red.withValues(alpha: 0.8),
                              blurRadius: 10,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // Content with Progress Overlay
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.grey.shade900],
          ),
        ),
        child: Stack(
          children: [
            // Main Content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 120, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [ResultsCarousel()],
              ),
            ),

            // Progress Overlay (Sits on top)
            const ProgressOverlay(),
          ],
        ),
      ),
    );
  }
}