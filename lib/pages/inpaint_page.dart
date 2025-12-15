// ==================== Inpaint Page ==================== //

// Flutter imports
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/image_upload_container.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Inpaint Page Class ========== //

class InpaintPage extends StatefulWidget {
  // ===== Constructor ===== //
  const InpaintPage({super.key});

  @override
  InpaintPageState createState() => InpaintPageState();
}

class InpaintPageState extends State<InpaintPage> {
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
                    'INPAINT CANVAS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Neon Status Bar
                  ValueListenableBuilder(
                    valueListenable: globalServerStatus,
                    builder: (context, value, child) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 80,
                        height: 4,
                        decoration: BoxDecoration(
                          color: value ? Colors.greenAccent : Colors.redAccent,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: value
                                  ? Colors.green.withValues(alpha: 0.8)
                                  : Colors.red.withValues(alpha: 0.8),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
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

      // Content
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.grey.shade900],
          ),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            // Extra padding at top for custom AppBar, bottom for nav bar clearance
            padding: const EdgeInsets.fromLTRB(16, 120, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Your drawing/upload container
                ImageContainer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
