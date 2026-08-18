// ==================== Aperture ==================== //
//
// The real Stage is not built yet (see DESIGN.md build order). Until it is,
// debug builds boot into the dev harness, which exercises the new framework
// and the glass material on a real device.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sd_companion/runtime/aperture_runtime.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/ui/dev/dev_harness.dart';
import 'package:sd_companion/ui/glass/glass_shader.dart';
import 'package:sd_companion/ui/glass/glass_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Compile/load the glass program once, before the first frame, so panes
  // never flash through their fallback on startup.
  await GlassShader.load();

  final runtime = await ApertureRuntime.boot();

  runApp(ApertureApp(runtime: runtime));
}

class ApertureApp extends StatelessWidget {
  final ApertureRuntime runtime;

  const ApertureApp({super.key, required this.runtime});

  @override
  Widget build(BuildContext context) {
    return RuntimeScope(
      runtime: runtime,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Aperture',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Palette.void_,
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Geist'),
        ),
        home: kDebugMode ? const DevHarness() : const _ComingSoon(),
      ),
    );
  }
}

/// Release builds have nothing to show yet. Deliberately blunt rather than
/// shipping the dev harness to a real user.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void_,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.blur_circular_rounded, size: 48, color: Palette.chalk40),
            const SizedBox(height: Space.lg),
            Text('Aperture', style: Type.stageTitle),
            const SizedBox(height: Space.sm),
            Text('Interface under construction', style: Type.body.copyWith(color: Palette.chalk40)),
          ],
        ),
      ),
    );
  }
}
