// ==================== Aperture ==================== //
//
// The real front page is not built yet (see DESIGN.md build order). Until it
// is, debug builds boot into the dev harness, which exercises the Desk
// design system and the runtime on a real device.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sd_companion/runtime/aperture_runtime.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';
import 'package:sd_companion/ui/dev/dev_harness.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

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
        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: DeskPalette.day.desk,
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Geist'),
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
    return Desk(
      child: Center(
        child: Builder(
          builder: (context) {
            final p = DeskTheme.of(context);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_rounded, size: 40, color: p.inkFaint),
                const SizedBox(height: Space.lg),
                Text('Aperture', style: Type.deskTitle.copyWith(color: p.ink)),
                const SizedBox(height: Space.sm),
                Text(
                  'Interface under construction',
                  style: Type.body.copyWith(color: p.inkFaint),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
