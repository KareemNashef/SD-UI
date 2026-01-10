// ==================== Metadata Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Metadata Modal Implementation

/// Shows a glassmorphic modal displaying generation metadata (prompts, parameters).
void showMetadataModal(BuildContext context, Map<String, String> infoMap) {
  GlassModal.show(context, child: _MetadataContent(infoMap: infoMap));
}

class _MetadataContent extends StatelessWidget {
  final Map<String, String> infoMap;

  const _MetadataContent({required this.infoMap});

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    // Separate prompts from the rest of the parameters
    final positivePrompt = infoMap['prompt'];
    final negativePrompt = infoMap['negativePrompt'];

    // Filter out prompts to create the parameters map
    final parameters = Map<String, String>.from(infoMap)
      ..remove('prompt')
      ..remove('negativePrompt');

    return Column(
      children: [
        const GlassHeader(
          title: 'Metadata',
          trailing: Icon(
            Icons.data_object,
            color: AppTheme.accentPrimary,
            size: 22,
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Positive Prompt
                if (positivePrompt != null && positivePrompt.isNotEmpty) ...[
                  _GlassSection(
                    title: 'Positive Prompt',
                    content: positivePrompt,
                    icon: Icons.add_circle_outline,
                    accentColor: AppTheme.success, // Greenish
                  ),
                  const SizedBox(height: 16),
                ],

                // Negative Prompt
                if (negativePrompt != null && negativePrompt.isNotEmpty) ...[
                  _GlassSection(
                    title: 'Negative Prompt',
                    content: negativePrompt,
                    icon: Icons.remove_circle_outline,
                    accentColor: AppTheme.error, // Reddish
                  ),
                  const SizedBox(height: 16),
                ],

                // Parameters Header
                if (parameters.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'PARAMETERS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                  // Parameters Grid
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: parameters.entries.map((entry) {
                      return _ParameterChip(
                        label: entry.key,
                        value: entry.value,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A glowing glass section for large text blocks (Prompts)
class _GlassSection extends StatelessWidget {
  final String title;
  final String content;
  final IconData icon;
  final Color accentColor;

  const _GlassSection({
    required this.title,
    required this.content,
    required this.icon,
    required this.accentColor,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.glassBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(
                  color: accentColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: accentColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                // Copy Button
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied $title'),
                        backgroundColor: AppTheme.glassBackgroundDark,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Icon(
                    Icons.copy,
                    color: accentColor.withValues(alpha: 0.6),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact glass chip for key-value parameters
class _ParameterChip extends StatelessWidget {
  final String label;
  final String value;

  const _ParameterChip({required this.label, required this.value});

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase().replaceAll('_', ' '),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
