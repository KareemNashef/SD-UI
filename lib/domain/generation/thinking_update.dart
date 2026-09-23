// ==================== Thinking Update ==================== //

import 'package:flutter/foundation.dart';

/// Where a local LLM has got to, mid-answer.
///
/// The prompt workflows run against an LM Studio server, which reports its
/// own lifecycle rather than a step count: it loads a model, reads the
/// prompt, reasons, then writes. A percentage bar cannot say any of that,
/// and the interesting part - the words appearing - is not a number at all.
///
/// So this carries the two things worth showing: which of those stages is
/// happening, and the text so far.
@immutable
class ThinkingUpdate {
  /// The server's own word for what it is doing: `connecting`, `loading`,
  /// `prompt`, `thinking`, `generating`, `done`, `error`, `cancelled`.
  /// Passed through rather than mapped to an enum, because a node that adds
  /// a stage should be able to say so without this file changing.
  final String phase;

  /// 0-1 while the server reports one, which it only does for model loading
  /// and prompt processing. Null the rest of the time - and "writing" has no
  /// honest percentage, since nothing knows how long the answer will be.
  final double? progress;

  /// The reasoning so far, if the model is one that reasons out loud.
  final String thinking;

  /// The answer so far.
  final String text;

  final bool done;
  final String? error;

  const ThinkingUpdate({
    required this.phase,
    this.progress,
    this.thinking = '',
    this.text = '',
    this.done = false,
    this.error,
  });

  static const idle = ThinkingUpdate(phase: 'idle');

  /// Whatever the model is currently putting out: its answer once that has
  /// started, its reasoning before then. One stream to read, which is what
  /// an indicator wants.
  String get stream => text.isNotEmpty ? text : thinking;

  bool get isActive => !done && phase != 'idle' && error == null;

  /// A short line for a caption. Deliberately not a translation table -
  /// an unrecognised phase reads out as itself rather than as nothing.
  String get label => switch (phase) {
        'idle' => '',
        'connecting' => 'REACHING THE MODEL',
        'connected' => 'REACHING THE MODEL',
        'loading' => 'LOADING THE MODEL',
        'loaded' => 'MODEL READY',
        'prompt' => 'READING THE PROMPT',
        'thinking' => 'THINKING',
        'generating' => 'WRITING',
        'done' => 'DONE',
        'cancelled' => 'CANCELLED',
        'error' => 'FAILED',
        _ => phase.toUpperCase(),
      };

  factory ThinkingUpdate.fromEvent(Map<String, dynamic> data) => ThinkingUpdate(
        phase: data['phase']?.toString() ?? 'thinking',
        progress: (data['progress'] as num?)?.toDouble(),
        thinking: data['thinking']?.toString() ?? '',
        text: data['text']?.toString() ?? '',
        done: data['done'] == true,
        error: data['error']?.toString(),
      );

  @override
  bool operator ==(Object other) =>
      other is ThinkingUpdate &&
      other.phase == phase &&
      other.progress == progress &&
      other.thinking == thinking &&
      other.text == text &&
      other.done == done &&
      other.error == error;

  @override
  int get hashCode => Object.hash(phase, progress, thinking, text, done, error);
}
