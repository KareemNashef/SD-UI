// ==================== Settings Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/settings/checkpoint_settings.dart';
import 'package:sd_companion/elements/settings/edit_settings.dart';
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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: const Scaffold(
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
              // Invisible dummy focus node to absorb focus restoration
              Focus(autofocus: true, child: SizedBox.shrink()),
              ServerSettings(),
              SizedBox(height: 24),
              CheckpointSettings(),
              SizedBox(height: 24),
              GenerationSettings(),
              SizedBox(height: 24),
              EditSettings(),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
