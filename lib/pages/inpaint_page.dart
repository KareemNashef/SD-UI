// ==================== Inpaint Page ==================== //

// Flutter imports
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
  // ===== Class Variables ===== //

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
              'Inpaint',
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
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImageContainer(),
              const SizedBox(height: 89),
            ],
          ),
        ),
      ),
    );
  }
}
