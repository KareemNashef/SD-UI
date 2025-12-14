// ==================== Generation Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modern_slider.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Generation Settings Class ========== //

class GenerationSettings extends StatefulWidget {
  const GenerationSettings({Key? key}) : super(key: key);

  @override
  State<GenerationSettings> createState() => GenerationSettingsState();
}

class GenerationSettingsState extends State<GenerationSettings> {
  // ===== Class Variables ===== //

  final negativePrompt = TextEditingController(text: globalNegativePrompt);

  // ===== Lifecycle Methods ===== //

  @override
  void dispose() {
    negativePrompt.dispose();
    super.dispose();
  }

  // ===== Class Widgets ===== //

  InputDecoration modernInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.2),
      
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.cyan.shade300.withValues(alpha: 0.5), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        // Theme
        decoration: BoxDecoration(
          color: Colors.grey.shade900.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),

        // Padding
        padding: const EdgeInsets.all(20.0),

        // Content
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title with Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.auto_awesome, color: Colors.purple.shade300, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Generation Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Sliders
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

            const SizedBox(height: 20),

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

            const SizedBox(height: 20),

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

            const SizedBox(height: 24),

            // Masked Content Toggle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    'Masked Content',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                
                Row(
                  children: [
                    _AnimatedSelectionChip(
                      label: 'Fill',
                      isSelected: globalMaskFill == 'fill',
                      onTap: () => setState(() { globalMaskFill = 'fill'; saveMaskFill(); }),
                    ),
                    const SizedBox(width: 8),
                    _AnimatedSelectionChip(
                      label: 'Original',
                      isSelected: globalMaskFill == 'original',
                      onTap: () => setState(() { globalMaskFill = 'original'; saveMaskFill(); }),
                    ),
                    const SizedBox(width: 8),
                    _AnimatedSelectionChip(
                      label: 'Noise',
                      isSelected: globalMaskFill == 'latent noise',
                      onTap: () => setState(() { globalMaskFill = 'latent noise'; saveMaskFill(); }),
                    ),
                    const SizedBox(width: 8),
                    _AnimatedSelectionChip(
                      label: 'Nothing',
                      isSelected: globalMaskFill == 'latent nothing',
                      onTap: () => setState(() { globalMaskFill = 'latent nothing'; saveMaskFill(); }),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Negative Prompt
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    'Negative Prompt',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                TextField(
                  controller: negativePrompt,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                  decoration: modernInputDecoration(hint: 'Enter negative prompt...'),
                  maxLines: 4,
                  minLines: 3,
                  onChanged: (value) {
                    globalNegativePrompt = value;
                    saveNegativePrompt();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// ANIMATED SELECTION CHIP
// ==========================================

class _AnimatedSelectionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedSelectionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? Colors.cyan.shade600 
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected 
                  ? Colors.cyan.shade400 
                  : Colors.white.withValues(alpha: 0.1),
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: Colors.cyan.shade600.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 0,
              )
            ] : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}