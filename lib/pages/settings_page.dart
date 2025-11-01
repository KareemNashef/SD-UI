// ==================== Settings Page ==================== //

// Flutter imports
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
  // ===== Class Variables ===== //

  // Controllers
  final serverIP = TextEditingController();
  final port = TextEditingController();

  // ===== Class Widgets ===== //

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
              'Settings',
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

      // Content
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Server Settings
              ServerSettings(),

              // Spacer
              const SizedBox(height: 16),

              // Checkpoint Settings
              CheckpointSettings(),

              // Spacer
              const SizedBox(height: 16),

              // Generation Settings
              GenerationSettings(),

              // Spacer
              const SizedBox(height: 89),
            ],
          ),
        ),
      ),
    );
  }
}
