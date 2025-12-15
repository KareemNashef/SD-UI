// ==================== Settings Page ==================== //

// Flutter imports
import 'dart:ui';
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/server_settings.dart';
import 'package:sd_companion/elements/checkpoint_settings.dart';
import 'package:sd_companion/elements/generation_settings.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Settings Page Class ========== //

class SettingsPage extends StatefulWidget {
  // ===== Constructor ===== //
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Allows content to scroll behind blur
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

              // Custom Title with Neon Status Bar
              title: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'SYSTEM SETTINGS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Animated Neon Status Bar
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
        // Optional: Subtle gradient background for the whole page
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
            // Extra top padding for the extended AppBar
            padding: const EdgeInsets.fromLTRB(16, 120, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Server Settings
                const ServerSettings(),

                // Spacer
                const SizedBox(height: 24),

                // Checkpoint Settings
                const CheckpointSettings(),

                // Spacer
                const SizedBox(height: 24),

                // Generation Settings
                const GenerationSettings(),

                // Bottom Spacer for navigation bar clearance
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
