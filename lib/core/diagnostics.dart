// ==================== Diagnostics ==================== //
//
// Tagged tracing for the generation path. It logs from release builds too,
// deliberately: the bugs worth chasing here only reproduce against a live
// server on real hardware, which no test harness can stand in for.
//
// Off by default: a run emits a line per progress frame and per preview,
// which is exactly what you want while chasing a bug and pure noise the
// rest of the time.
//
// To debug a generation, flip [kApertureTrace] to true, rebuild, and
// capture with:
//   adb logcat -c && adb logcat -s flutter:V | findstr aperture
//
// The server side has its own switch - see comfy_addon/README.md - and the
// two are independent, so either can be read on its own.

import 'package:flutter/foundation.dart';

/// Master switch for generation tracing. Off in normal use.
const bool kApertureTrace = false;

/// One line of trace, tagged by subsystem so logcat can be filtered.
///
/// `[aperture/<area>] <message>` - grep `aperture` for everything, or
/// `aperture/ws` for just the socket.
void trace(String area, String message) {
  if (!kApertureTrace) return;
  debugPrint('[aperture/$area] $message');
}

/// Milliseconds since the process started, so relative ordering and gaps
/// between frames are visible without wall-clock noise.
final Stopwatch _since = Stopwatch()..start();

String get traceClock => '${_since.elapsedMilliseconds}ms';
