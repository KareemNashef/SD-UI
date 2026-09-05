// ==================== Aperture ==================== //

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sd_companion/runtime/aperture_runtime.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';
import 'package:sd_companion/ui/stage/front_page.dart';

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
        home: const FrontPage(),
      ),
    );
  }
}
