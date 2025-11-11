// ==================== Checkpoint Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modern_slider.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Checkpoint Settings Class ========== //

class GenerationSettings extends StatefulWidget {
  const GenerationSettings({Key? key}) : super(key: key);

  @override
  State<GenerationSettings> createState() => GenerationSettingsState();
}

class GenerationSettingsState extends State<GenerationSettings> {
  // ===== Class Variables ===== //

  // Controller
  final negativePrompt = TextEditingController(text: globalNegativePrompt);

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    negativePrompt.dispose();
    super.dispose();
  }

  // ===== Class Widgets ===== //

  InputDecoration modernInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withAlpha(128)),

      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.1),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),

      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Container(
        // Theme
        decoration: BoxDecoration(
          color: Colors.grey.shade800.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),

        // Padding
        padding: const EdgeInsets.all(16.0),

        // Content
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title with Icon
            Row(
              children: [
                Icon(
                  Icons.brush,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Generation Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),

            // Spacer
            const SizedBox(height: 24),

            // Denoising Strength
            ModernSlider(
              label: 'Denoising Strength',
              value: globalDenoiseStrength,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              onChanged: (value) {
                setState(() {
                  globalDenoiseStrength = value;
                  saveDenoiseStrength();
                });
              },
              valueFormatter: (val) => val.toStringAsFixed(2),
            ),

            // Spacer
            const SizedBox(height: 20),

            // Mask Blur
            ModernSlider(
              label: 'Mask Blur',
              value: globalMaskBlur.toDouble(),
              min: 0,
              max: 16,
              divisions: 16,
              onChanged: (value) {
                setState(() {
                  globalMaskBlur = value.toInt();
                  saveMaskBlur();
                });
              },
              valueFormatter: (val) => val.toInt().toString(),
            ),

            // Spacer
            const SizedBox(height: 20),

            // Batch Size
            ModernSlider(
              label: 'Batch Size',
              value: globalBatchSize.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (value) {
                setState(() {
                  globalBatchSize = value.toInt();
                  saveBatchSize();
                });
              },
              valueFormatter: (val) => val.toInt().toString(),
            ),

            // Spacer
            const SizedBox(height: 20),

            // Masked Content Toggle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Masked Content',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),

                // Spacer
                const SizedBox(height: 16),

                // Options
                Row(
                  children: [
                    // Fill Option
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          globalMaskFill = 'fill';
                          saveMaskFill();
                        }),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 800),
                          opacity: globalMaskFill == 'fill' ? 1.0 : 0.2,
                          curve: Curves.easeInOut,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.cyan.shade400,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Fill',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Spacer
                    const SizedBox(width: 8),

                    // Original Option
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          globalMaskFill = 'original';
                          saveMaskFill();
                        }),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 800),
                          opacity: globalMaskFill == 'original' ? 1.0 : 0.2,
                          curve: Curves.easeInOut,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.cyan.shade400,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Original',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Spacer
                    const SizedBox(width: 8),

                    // Latent Noise Option
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          globalMaskFill = 'latent noise';
                          saveMaskFill();
                        }),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 800),
                          opacity: globalMaskFill == 'latent noise' ? 1.0 : 0.2,
                          curve: Curves.easeInOut,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.cyan.shade400,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Noise',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Spacer
                    const SizedBox(width: 8),

                    // Latent Nothing Option
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          globalMaskFill = 'latent nothing';
                          saveMaskFill();
                        }),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 800),
                          opacity: globalMaskFill == 'latent nothing'
                              ? 1.0
                              : 0.2,
                          curve: Curves.easeInOut,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.cyan.shade400,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Nothing',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Spacer
            const SizedBox(height: 20),

            // Negative Prompt - Title
            const Text(
              'Negative Prompt',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),

            // Spacer
            const SizedBox(height: 16),

            // Negative Prompt - Text Field
            TextField(
              controller: negativePrompt,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: modernInputDecoration(hint: 'Negative Prompt'),
              maxLines: null,
              minLines: 3,
              onChanged: (value) {
                globalNegativePrompt = value;
                saveNegativePrompt();
              },
            ),
          ],
        ),
      ),
    );
  }
}
