// ==================== Settings Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/settings/backend_selector.dart';
import 'package:sd_companion/elements/settings/checkpoint_settings.dart';
import 'package:sd_companion/elements/settings/comfy_workflow_settings.dart';
import 'package:sd_companion/elements/settings/generation_settings.dart';
import 'package:sd_companion/elements/settings/server_settings.dart';
import 'package:sd_companion/elements/widgets/glass_app_bar.dart';

// Local imports - Logic
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/globals.dart';

// Settings Page Implementation

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage>
    with AutomaticKeepAliveClientMixin {
  // ===== Build Methods ===== //

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // REQUIRED!

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: const GlassAppBar(
          title: 'Settings',
          actions: [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: BackendIdentityBadge(compact: true),
            ),
          ],
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 110, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Invisible dummy focus node to absorb focus restoration
              const Focus(autofocus: true, child: SizedBox.shrink()),
              const SizedBox(height: 16),
              const BackendSelector(),
              const SizedBox(height: 24),
              const ServerSettings(),
              const SizedBox(height: 24),
              ValueListenableBuilder<BackendKind>(
                valueListenable: globalActiveBackendKind,
                builder: (context, kind, child) => kind == BackendKind.forge
                    ? const CheckpointSettings()
                    : const ComfyWorkflowSettings(),
              ),
              const SizedBox(height: 24),
              const GenerationSettings(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
