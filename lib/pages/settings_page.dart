// ==================== Settings Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/settings/checkpoint_settings.dart';
import 'package:sd_companion/elements/settings/generation_settings.dart';
import 'package:sd_companion/elements/settings/server_settings.dart';
import 'package:sd_companion/elements/widgets/glass_app_bar.dart';

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

    return const Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: 'SYSTEM'),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 110, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServerSettings(),
            SizedBox(height: 24),
            CheckpointSettings(),
            SizedBox(height: 24),
            GenerationSettings(),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
