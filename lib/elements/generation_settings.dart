// ==================== Checkpoint Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';

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
            const SizedBox(height: 16),

            // Denoising Strength
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Denoising Strength',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                // Spacer
                const SizedBox(height: 2),

                // Slider
                Row(
                  children: [
                    // Slider
                    Expanded(
                      child: Slider(
                        value: globalDenoiseStrength,
                        min: 0.1,
                        max: 1.0,
                        divisions: 18,
                        activeColor: Colors.purple.shade400,
                        inactiveColor: Colors.white.withAlpha(77),
                        onChanged: (value) {
                          setState(() {
                            globalDenoiseStrength = value;
                            saveDenoiseStrength();
                          });
                        },
                      ),
                    ),

                    // Spacer
                    const SizedBox(width: 8),

                    // Current Steps
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade400.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        globalDenoiseStrength.toStringAsFixed(1),
                        style: TextStyle(
                          color: Colors.white.withAlpha(204),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Spacer
            const SizedBox(height: 16),

            // Mask Blur
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Mask Blur',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                // Spacer
                const SizedBox(height: 2),

                // Slider
                Row(
                  children: [
                    // Slider
                    Expanded(
                      child: Slider(
                        value: globalMaskBlur.toDouble(),
                        min: 0,
                        max: 64,
                        divisions: 64,
                        activeColor: Colors.purple.shade400,
                        inactiveColor: Colors.white.withAlpha(77),
                        onChanged: (value) {
                          setState(() {
                            globalMaskBlur = value.toInt();
                            saveMaskBlur();
                          });
                        },
                      ),
                    ),

                    // Spacer
                    const SizedBox(width: 8),

                    // Current Steps
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade400.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        globalMaskBlur.toString(),
                        style: TextStyle(
                          color: Colors.white.withAlpha(204),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Spacer
            const SizedBox(height: 16),

            // Batch Size
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Batch Size',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                // Spacer
                const SizedBox(height: 2),

                // Slider
                Row(
                  children: [
                    // Slider
                    Expanded(
                      child: Slider(
                        value: globalBatchSize.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        activeColor: Colors.purple.shade400,
                        inactiveColor: Colors.white.withAlpha(77),
                        onChanged: (value) {
                          setState(() {
                            globalBatchSize = value.toInt();
                            saveBatchSize();
                          });
                        },
                      ),
                    ),

                    // Spacer
                    const SizedBox(width: 8),

                    // Current Steps
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade400.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        globalBatchSize.toString(),
                        style: TextStyle(
                          color: Colors.white.withAlpha(204),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Spacer
            const SizedBox(height: 16),

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
                              color: Colors.purple.shade400,
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
                              color: Colors.purple.shade400,
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
                              color: Colors.purple.shade400,
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
                              color: Colors.purple.shade400,
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
            const SizedBox(height: 16),

            // Negative Prompt - Title
            const Text(
              'Negative Prompt',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
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
