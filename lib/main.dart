// ==================== Aperture ==================== //
//
// TEMPORARY SHELL - placeholder only.
//
// The UI is being rebuilt from scratch (see DESIGN.md). This file exists
// solely so the project stays compilable and testable while the new
// interface is built feature by feature against the logic layer in
// lib/logic/. It will be replaced wholesale by the real app shell.

import 'package:flutter/material.dart';

import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Boot the logic layer so the placeholder can report real state.
  await StorageService.loadActiveBackendKind();
  await StorageService.loadServerSettings();
  await StorageService.loadComfyServerSettings();

  runApp(const ApertureApp());
}

class ApertureApp extends StatelessWidget {
  const ApertureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aperture',
      theme: ThemeData.dark(),
      home: const _RebuildPlaceholder(),
    );
  }
}

class _RebuildPlaceholder extends StatelessWidget {
  const _RebuildPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.blur_circular_rounded, size: 56, color: Color(0xFFB9C4F0)),
            const SizedBox(height: 20),
            const Text(
              'Aperture',
              style: TextStyle(color: Color(0xFFF3F1F7), fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'UI rebuild in progress',
              style: TextStyle(color: const Color(0xFFF3F1F7).withValues(alpha: 0.5), fontSize: 13),
            ),
            const SizedBox(height: 24),
            Text(
              'Logic layer online · engine: ${globalActiveBackendKind.value.displayName}',
              style: TextStyle(color: const Color(0xFFF3F1F7).withValues(alpha: 0.3), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
