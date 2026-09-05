// ==================== Session Store ==================== //

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/store.dart';
import 'package:sd_companion/domain/drawing/stroke.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/sampling_params.dart';

/// What the user is composing right now: the prompt, the source image, the
/// mask, and the settings that will be used.
///
/// This is the store that most directly replaces the god-module. Twelve of
/// the twenty unobservable globals lived here (`globalPositivePrompt`,
/// `globalCurrentSamplingSteps`, `globalMaskBlur`, ...). Because they were
/// plain mutable fields, nothing could rebuild when they changed - the old
/// UI papered over it with manual `setState` and, on engine switch, by
/// remounting the entire widget tree. Everything here is observable.
///
/// The session knows how to describe itself as a [GenerationSpec], which is
/// the only thing an engine is ever handed.
@immutable
class SessionState {
  final String prompt;
  final String negativePrompt;

  /// Source image on the canvas, if any.
  final File? sourceImage;

  /// Rendered mask for the current strokes. Produced by the canvas when the
  /// user paints; null when there is nothing masked.
  final Uint8List? mask;

  /// The strokes behind [mask], when it was painted by hand. Kept so the
  /// editor can be reopened on an existing mask instead of making the user
  /// redraw it; null for a mask that has no strokes to reopen (an outpaint
  /// border, say).
  final MaskDraft? maskDraft;

  final SamplingParams sampling;

  /// Forge only: extra images for the stitch script.
  final List<File> stitchImages;

  /// ComfyUI only: extra named image slots, keyed by graph node id.
  final Map<String, Uint8List> namedImages;

  const SessionState({
    this.prompt = '',
    this.negativePrompt = '',
    this.sourceImage,
    this.mask,
    this.maskDraft,
    this.sampling = const SamplingParams(),
    this.stitchImages = const [],
    this.namedImages = const {},
  });

  bool get hasPrompt => prompt.trim().isNotEmpty;
  bool get hasSourceImage => sourceImage != null;

  /// What kind of run this session currently describes.
  GenerationMode get mode {
    if (sourceImage == null) return GenerationMode.textToImage;
    if (mask != null) return GenerationMode.inpaint;
    return GenerationMode.imageToImage;
  }

  SessionState copyWith({
    String? prompt,
    String? negativePrompt,
    File? sourceImage,
    Uint8List? mask,
    MaskDraft? maskDraft,
    SamplingParams? sampling,
    List<File>? stitchImages,
    Map<String, Uint8List>? namedImages,
    bool clearSourceImage = false,
    bool clearMask = false,
  }) =>
      SessionState(
        prompt: prompt ?? this.prompt,
        negativePrompt: negativePrompt ?? this.negativePrompt,
        sourceImage: clearSourceImage ? null : (sourceImage ?? this.sourceImage),
        mask: clearMask ? null : (mask ?? this.mask),
        // The draft belongs to the mask: it is replaced whenever the mask
        // is, so a stale set of strokes can never be reopened over a
        // different mask.
        maskDraft: clearMask ? null : (mask != null ? maskDraft : this.maskDraft),
        sampling: sampling ?? this.sampling,
        stitchImages: stitchImages ?? this.stitchImages,
        namedImages: namedImages ?? this.namedImages,
      );

  @override
  bool operator ==(Object other) =>
      other is SessionState &&
      other.prompt == prompt &&
      other.negativePrompt == negativePrompt &&
      other.sourceImage?.path == sourceImage?.path &&
      identical(other.mask, mask) &&
      identical(other.maskDraft, maskDraft) &&
      other.sampling == sampling &&
      listEquals(other.stitchImages, stitchImages) &&
      mapEquals(other.namedImages, namedImages);

  @override
  int get hashCode => Object.hash(prompt, negativePrompt, sourceImage?.path,
      mask, sampling, Object.hashAll(stitchImages), Object.hashAll(namedImages.keys));
}

class SessionStore extends Store<SessionState> {
  SessionStore([SessionState? initial]) : super(initial ?? const SessionState());

  // ===== Prompt ===== //

  void setPrompt(String value) => update((s) => s.copyWith(prompt: value));

  void setNegativePrompt(String value) =>
      update((s) => s.copyWith(negativePrompt: value));

  void clearPrompt() => update((s) => s.copyWith(prompt: ''));

  // ===== Canvas ===== //

  void setSourceImage(File? file) => update(
        (s) => file == null
            // Dropping the image also drops the mask: a mask without the
            // image it was painted on is meaningless, and keeping it around
            // was how the old code ended up sending mismatched pairs.
            ? s.copyWith(clearSourceImage: true, clearMask: true)
            : s.copyWith(sourceImage: file, clearMask: true),
      );

  /// [draft] is the strokes that produced [mask], when there are any.
  /// Passing a mask without one (an outpaint border) deliberately drops any
  /// previous draft rather than leaving strokes that no longer match.
  void setMask(Uint8List? mask, {MaskDraft? draft}) => update(
        (s) => mask == null
            ? s.copyWith(clearMask: true)
            : s.copyWith(mask: mask, maskDraft: draft),
      );

  void clearCanvas() => update(
        (s) => s.copyWith(clearSourceImage: true, clearMask: true),
      );

  // ===== Sampling ===== //

  void setSampling(SamplingParams params) =>
      update((s) => s.copyWith(sampling: params));

  /// Applies a partial change to the sampling params without the caller
  /// having to rebuild the whole object.
  void tuneSampling(SamplingParams Function(SamplingParams current) transform) =>
      update((s) => s.copyWith(sampling: transform(s.sampling)));

  // ===== Engine-specific extras ===== //

  void addStitchImage(File file) =>
      update((s) => s.copyWith(stitchImages: [...s.stitchImages, file]));

  void removeStitchImage(int index) => update((s) {
        if (index < 0 || index >= s.stitchImages.length) return s;
        final next = [...s.stitchImages]..removeAt(index);
        return s.copyWith(stitchImages: next);
      });

  void setNamedImage(String nodeId, Uint8List? bytes) => update((s) {
        final next = {...s.namedImages};
        if (bytes == null) {
          next.remove(nodeId);
        } else {
          next[nodeId] = bytes;
        }
        return s.copyWith(namedImages: next);
      });

  /// Builds the complete spec for a run. Image bytes are read here rather
  /// than held in state, so the session keeps a file handle instead of a
  /// second copy of every image in memory.
  Future<GenerationSpec> toSpec() async {
    final s = state;
    final source = s.sourceImage == null ? null : await s.sourceImage!.readAsBytes();

    final stitch = <String>[];
    for (final file in s.stitchImages) {
      stitch.add(base64Encode(await file.readAsBytes()));
    }

    return GenerationSpec(
      prompt: s.prompt,
      negativePrompt: s.negativePrompt,
      sourceImage: source,
      mask: s.mask,
      sampling: s.sampling,
      stitchImages: stitch,
      namedImages: s.namedImages,
    );
  }
}

