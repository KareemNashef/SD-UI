// ==================== Server Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/pages/edit_page.dart';

// You need to import your EditPage here, or ensure it exists in the project
// import 'package:sd_companion/pages/edit_page.dart';

class EditSettings extends StatefulWidget {
  const EditSettings({super.key});
  @override
  State<EditSettings> createState() => EditSettingsState();
}

class EditSettingsState extends State<EditSettings>
    with SingleTickerProviderStateMixin {
  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: GlassContainer(
        backgroundColor: AppTheme.surfaceCard,
        borderColor: AppTheme.glassBorder,
        borderRadius: AppTheme.radiusLarge,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== Header Row ===== //
            Row(
              children: [
                // Edit Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: AppTheme.error,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 14),

                // Action Button
                // Wrapped in Expanded because the container inside uses width: double.infinity
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EditPage()),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.success,
                            AppTheme.success.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.success.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      // Added a child so the button has a label
                      child: const Center(
                        child: Text(
                          "Edit Settings",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
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
      ),
    );
  }
}
