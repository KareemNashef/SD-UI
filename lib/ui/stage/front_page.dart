// ==================== Front Page ==================== //
//
// The real app, assembled from the Desk components in `ui/desk/` and the
// stores/runtime `generation_lab.dart` proved out.
//
// Second pass, after real-device feedback split the Stage in two: a small,
// fixed input card for the source image (img2img/inpaint only) and a large
// main display that shows whatever the user is actually looking at - the
// live preview while generating, a result they tapped in the shelf, or a
// plain "nothing yet" placeholder for a fresh txt2img session. Tapping a
// print no longer just highlights it in the shelf; it becomes what the
// main display shows, and the tray swaps to the tools that apply to a
// finished result (save, upscale, delete - edit and crop are listed but not
// wired yet) instead of the compose-time tools.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sd_companion/core/diagnostics.dart';
import 'package:sd_companion/core/store.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow_type.dart';
import 'package:sd_companion/data/engines/forge/forge_catalog_client.dart';
import 'package:sd_companion/domain/catalog/checkpoint.dart';
import 'package:sd_companion/domain/engine/engine_capabilities.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/engine/image_engine.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';
import 'package:sd_companion/domain/generation/sampler_names.dart';
import 'package:sd_companion/domain/generation/sampling_params.dart';
import 'package:sd_companion/domain/generation/scheduler_names.dart';
import 'package:sd_companion/runtime/aperture_runtime.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/state/catalog_store.dart';
import 'package:sd_companion/state/engine_store.dart';
import 'package:sd_companion/state/library_store.dart';
import 'package:sd_companion/state/run_store.dart';
import 'package:sd_companion/state/session_store.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';
import 'package:sd_companion/ui/dev/dev_harness.dart';
import 'package:sd_companion/data/imaging/image_processor.dart';
import 'package:sd_companion/data/imaging/png_metadata.dart';
import 'package:sd_companion/ui/stage/civitai_page.dart';
import 'package:sd_companion/ui/stage/crop_editor.dart';
import 'package:sd_companion/ui/stage/gallery_page.dart';
import 'package:sd_companion/ui/stage/image_tools.dart';
import 'package:sd_companion/ui/stage/mask_editor.dart';
import 'package:sd_companion/ui/stage/outpaint_editor.dart';
import 'package:sd_companion/ui/stage/prompt_book.dart';
import 'package:sd_companion/ui/stage/workflow_settings.dart';

/// The source image's identity on the shelf. Namespaced so it can never
/// collide with a `GeneratedImage.id` (those are microsecond timestamps).
const kInputPrintId = '__aperture_input__';

/// The run in flight, as a card on the shelf. Giving it an identity is what
/// lets the stage treat "watching this generate" as one more thing you can
/// be looking at, rather than a mode that takes the screen for its duration.
const kRunPrintId = '__aperture_run__';

class FrontPage extends StatefulWidget {
  const FrontPage({super.key});

  @override
  State<FrontPage> createState() => _FrontPageState();
}

class _FrontPageState extends State<FrontPage> {
  final _prompt = TextEditingController();
  final _picker = ImagePicker();

  late final StoreGroup _stores;
  bool _connecting = false;

  /// The shelf id of whatever the main display is showing: a result's id,
  /// [_kInputId] for the source image, or null for "nothing picked yet".
  /// One field rather than a bool plus an id, so the two can't disagree
  /// about what's on screen.
  String? _viewingId;

  static const _kInputId = kInputPrintId;
  static const _kRunId = kRunPrintId;

  /// True while the compare tool is held down. It only swaps which child of
  /// the already-mounted IndexedStack is painted, so the flip costs nothing.
  bool _comparing = false;

  /// Which prompt action is in flight, if any. A single shared bool made
  /// *both* buttons show as working whichever one was pressed - the busy
  /// state has to identify the task, not just its existence.
  _PromptTask? _promptTask;

  bool get _promptBusy => _promptTask != null;

  /// Whether the second prompt button writes a new prompt instead of
  /// rewriting the one you have. Held rather than tapped to change: the two
  /// are alternatives to each other, not a pair worth a button each in a row
  /// that already has three.
  bool _promptGenerates = false;

  /// The one number the prompt writer takes: 1 mild, 10 extreme. Kept for
  /// the session rather than asked for each time - it is a setting you land
  /// on and then press the button repeatedly at.
  double _promptIntensity = 5;

  /// The toggle, but only where the engine can honour it - switching to an
  /// engine that cannot write prompts must not leave a button that does
  /// nothing but apologise.
  bool get _generating =>
      _promptGenerates && _rt.engine.state.capabilities.promptGenerate;

  void _togglePromptTool() {
    setState(() => _promptGenerates = !_promptGenerates);
    HapticFeedback.mediumImpact();
    _notify(_promptGenerates
        ? 'Write: makes a prompt from nothing.'
        : 'Enhance: rewrites the prompt you have.');
  }

  /// The prompt as it was before the last wholesale replacement - a clear,
  /// an enhance, a description, a prompt lifted from the book or Civitai.
  /// Typing is not a replacement and does not touch this.
  ///
  /// Undo *swaps* rather than pops, so pressing it twice returns to where
  /// you were: an accidental undo cannot destroy anything either.
  String? _promptUndo;

  /// Zoom and pan for the main display. Deliberately *one* controller shared
  /// by every image on the stage: holding compare must land the input at the
  /// exact same magnification and position, or the comparison is worthless.
  final TransformationController _view = TransformationController();

  ApertureRuntime get _rt => RuntimeScope.read(context);

  @override
  void initState() {
    super.initState();
    final rt = RuntimeScope.read(context);
    _prompt.text = rt.session.state.prompt;
    _stores = StoreGroup([rt.engine, rt.session, rt.run, rt.library, rt.catalog]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connect(rt.engine.state.active);
    });
  }

  @override
  void dispose() {
    _view.dispose();
    _stores.dispose();
    _prompt.dispose();
    super.dispose();
  }

  // ===== Connection ===== //

  Future<void> _connect(EngineKind kind, {EngineEndpoint? withEndpoint}) async {
    final previous = _rt.engine.state.endpoints[kind]!;
    final endpoint = withEndpoint ?? previous;

    setState(() => _connecting = true);

    if (withEndpoint != null && withEndpoint != previous) {
      await _rt.engines.invalidate(previous);
    }
    _rt.engine.setEndpoint(endpoint);
    _rt.engine.setActive(kind);
    _rt.engine.markConnecting();

    final engine = _rt.engines.of(endpoint);
    final reachable = await engine.ping();
    if (!mounted) return;
    if (!reachable) {
      _rt.engine.markUnreachable('No answer from ${endpoint.display}');
      setState(() => _connecting = false);
      return;
    }
    _rt.engine.markConnected();

    switch (kind) {
      case EngineKind.forge:
        final result = await ForgeCatalogClient(endpoint: endpoint).fetchCheckpoints();
        result.fold(
          _rt.catalog.setCheckpoints,
          (error) => _notify(error.message, isError: true),
        );
      case EngineKind.comfy:
        // Just restore whatever this server already has saved - no more
        // silently importing a bundled debug workflow.
        await _rt.engines.workflowsFor(endpoint).loadFor(endpoint);
    }

    if (mounted) setState(() => _connecting = false);
  }

  bool _isReady(EngineState engineState, ComfyWorkflowService? workflows) {
    if (!engineState.isConnected) return false;
    if (engineState.active == EngineKind.comfy) {
      return workflows?.activeDetected.value != null;
    }
    return true;
  }

  // ===== Source image ===== //

  Future<void> _pickSourceImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    _rt.session.setSourceImage(File(picked.path));
    // Show it at once. Previously the picture went into the session but the
    // main display stayed on whatever was there before, so choosing an image
    // looked like it had done nothing.
    setState(() => _viewingId = _kInputId);
  }

  // ===== Generation ===== //

  Future<void> _generate() async {
    // Land on the run's own card, so the progress preview is what is on the
    // stage - but as a *selection*, which means the user can move off it to
    // an earlier result and come back by tapping the card again.
    setState(() => _viewingId = _kRunId);
    final result = await _rt.submit();
    if (!mounted) return;
    result.fold(
      (images) {
        if (images.isNotEmpty) setState(() => _viewingId = images.first.id);
      },
      (error) => _notify(error.message, isError: true),
    );
  }

  // ===== Crop / resize / metadata ===== //

  /// Resolves whichever image the tray is currently acting on: a focused
  /// result, or the source image when that is what's on the stage.
  Future<(Uint8List bytes, bool isSource)?> _activeImageBytes(
      LibraryState library) async {
    final focused = _focusedImage(library);
    if (focused != null) {
      final bytes = await _imageBytes(focused);
      return bytes == null ? null : (bytes, false);
    }
    final file = _rt.session.state.sourceImage;
    if (file == null) return null;
    try {
      return (await file.readAsBytes(), true);
    } catch (_) {
      return null;
    }
  }

  /// Writes edited bytes back where they came from: a source image is
  /// replaced in place, while an edited *result* becomes a new print rather
  /// than overwriting the one that was generated.
  Future<void> _applyEditedBytes(Uint8List bytes, bool isSource) async {
    if (isSource) {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/aperture_edit_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      _rt.session.setSourceImage(file);
      setState(() => _viewingId = _kInputId);
      return;
    }
    final url = 'data:image/png;base64,${base64Encode(bytes)}';
    _rt.library.add([GeneratedImage.fromTool(url, _rt.engine.state.active)]);
    if (mounted) setState(() => _viewingId = _rt.library.state.selectedId);
  }

  Future<void> _openCropEditor(LibraryState library) async {
    final target = await _activeImageBytes(library);
    if (!mounted || target == null) {
      if (mounted) _notify('Could not read that image.', isError: true);
      return;
    }
    final decoded = await decodeImageFromList(target.$1);
    if (!mounted) return;

    final cropped = await Navigator.of(context).push<Uint8List?>(
      DeskPageRoute(
        builder: (_) => CropEditor(
          image: decoded,
          bytes: target.$1,
          display: MemoryImage(target.$1),
        ),
        fullscreenDialog: true,
      ),
    );
    decoded.dispose();
    if (!mounted || cropped == null) return;
    await _applyEditedBytes(cropped, target.$2);
    if (mounted) _notify('Cropped.');
  }

  Future<void> _openResizeDrawer(LibraryState library) async {
    final target = await _activeImageBytes(library);
    if (!mounted || target == null) {
      if (mounted) _notify('Could not read that image.', isError: true);
      return;
    }
    final decoded = await decodeImageFromList(target.$1);
    if (!mounted) return;
    final width = decoded.width;
    final height = decoded.height;
    decoded.dispose();

    await showDeskDrawer<void>(
      context: context,
      title: 'Resize',
      builder: (context) => ResizeDrawerBody(
        width: width,
        height: height,
        onApply: (w, h) async {
          final resized =
              await resizeImageBytes(bytes: target.$1, width: w, height: h);
          if (!mounted) return;
          if (resized == null) {
            _notify('Resize failed.', isError: true);
            return;
          }
          await _applyEditedBytes(resized, target.$2);
          if (mounted) _notify('Resized to $w × $h.');
        },
      ),
    );
  }

  /// CHECKLIST 5.5. Reads the PNG's own text chunks - no server call, which
  /// is why this works on any image, from any source, at any time.
  Future<void> _openMetadataDrawer(LibraryState library) async {
    final target = await _activeImageBytes(library);
    if (!mounted || target == null) {
      if (mounted) _notify('Could not read that image.', isError: true);
      return;
    }
    final metadata = readImageMetadata(target.$1);
    if (!mounted) return;

    await showDeskDrawer<void>(
      context: context,
      title: 'Image details',
      builder: (context) => MetadataDrawerBody(
        metadata: metadata,
        onCopied: _notify,
      ),
    );
  }

  /// A full-screen prompt editor.
  ///
  /// Two rows is right for the common case and hopeless for a long one -
  /// editing the middle of a paragraph through a two-line window means
  /// scrolling blind. This gives the whole screen to the text and hands it
  /// back on close.
  Future<void> _openPromptEditor() async {
    final edited = await Navigator.of(context).push<String>(
      DeskPageRoute(
        builder: (_) => _PromptEditorPage(initial: _prompt.text),
        fullscreenDialog: true,
      ),
    );
    if (edited == null || !mounted) return;
    _setPrompt(edited);
  }

  /// CHECKLIST 7.1: the server's own output history.
  ///
  /// Whatever is chosen there comes back as `GeneratedImage`s and joins the
  /// shelf, so a server image behaves exactly like one this session made -
  /// it can be compared, cropped, upscaled or sent to the input with no
  /// special handling anywhere downstream.
  Future<void> _openGallery() async {
    final engineState = _rt.engine.state;
    if (!engineState.capabilities.serverLibrary) {
      _notify('This engine has no browsable server library.', isError: true);
      return;
    }
    final picked = await Navigator.of(context).push<List<GeneratedImage>>(
      DeskPageRoute(
        builder: (_) => GalleryPage(endpoint: engineState.endpoint),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    _rt.library.add(picked);
    setState(() => _viewingId = _rt.library.state.selectedId);
    _notify('Added ${picked.length} image${picked.length == 1 ? '' : 's'} '
        'from the server.');
  }

  // ===== Prompt intelligence (Tier 6) ===== //

  /// Replaces the prompt wholesale, remembering what was there.
  /// [remember] is false only for the undo itself, which manages the swap.
  void _setPrompt(String value, {bool remember = true}) {
    final previous = _prompt.text;
    _prompt.text = value;
    _prompt.selection = TextSelection.collapsed(offset: value.length);
    _rt.session.setPrompt(value);
    if (remember && previous != value) {
      setState(() => _promptUndo = previous);
    }
  }

  void _undoPrompt() {
    final restore = _promptUndo;
    if (restore == null) return;
    final current = _prompt.text;
    _setPrompt(restore, remember: false);
    setState(() => _promptUndo = current);
  }

  Future<void> _openPromptBook() => showDeskDrawer<void>(
        context: context,
        title: 'Prompts',
        builder: (context) => PromptBookBody(
          store: _rt.promptBook,
          onUse: _setPrompt,
          onAppend: (fragment) {
            final current = _prompt.text.trim();
            _setPrompt(current.isEmpty ? fragment : '$current, $fragment');
          },
        ),
      );

  /// CHECKLIST 6.4. ComfyUI runs a bundled QwenVL workflow for this, so it
  /// takes real time and can fail - hence the notice on both ends rather
  /// than a silent swap of the text under the cursor.
  Future<void> _enhancePrompt() async {
    final engine = _rt.activeEngine;
    if (engine is! PromptRewriteCapable) {
      _notify('This engine cannot rewrite prompts.', isError: true);
      return;
    }
    final current = _prompt.text.trim();
    if (current.isEmpty) {
      _notify('Type something first - there is nothing to enhance.');
      return;
    }
    if (_rt.run.isActive) {
      _notify('Something is already running.', isError: true);
      return;
    }

    setState(() => _promptTask = _PromptTask.enhance);
    final result = await (engine as PromptRewriteCapable).rewritePrompt(current);
    if (!mounted) return;
    setState(() => _promptTask = null);
    result.fold(
      (rewritten) {
        // The original goes into the book first, so an enhancement that
        // turns out worse is one tap away from being undone.
        _rt.promptBook.record(current);
        _setPrompt(rewritten);
        _notify('Prompt enhanced. The original is saved under Prompts.');
      },
      (error) => _notify(error.message, isError: true),
    );
  }

  /// The other half of the enhance button. Takes nothing and returns a
  /// whole prompt, so it is the tool for an empty box - which is exactly
  /// when "enhance" has nothing to work with.
  Future<void> _generatePrompt() async {
    final engine = _rt.activeEngine;
    if (engine is! PromptGenerateCapable) {
      _notify('This engine cannot write prompts on its own.', isError: true);
      return;
    }
    if (_rt.run.isActive) {
      _notify('Something is already running.', isError: true);
      return;
    }

    setState(() => _promptTask = _PromptTask.generate);
    final result = await (engine as PromptGenerateCapable)
        .generatePrompt(intensity: _promptIntensity.round());
    if (!mounted) return;
    setState(() => _promptTask = null);
    result.fold(
      (prompt) {
        // Whatever was there goes to the book first, and the prompt row's
        // undo covers the swap either way.
        final current = _prompt.text.trim();
        if (current.isNotEmpty) _rt.promptBook.record(current);
        _setPrompt(prompt);
        _notify('Prompt written. Hold Write again for Enhance.');
      },
      (error) => _notify(error.message, isError: true),
    );
  }

  /// CHECKLIST 6.5. Captions the source image into a prompt.
  Future<void> _describeImage() async {
    final engine = _rt.activeEngine;
    if (engine is! ImageToTextCapable) {
      _notify('This engine cannot describe images.', isError: true);
      return;
    }
    if (_rt.run.isActive) {
      _notify('Something is already running.', isError: true);
      return;
    }

    // Picks its own image rather than reading the session's source. That
    // makes "turn this photo into a prompt" available in a txt2img workflow
    // too, where there is no input image at all - which is arguably the case
    // where describing is most useful.
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await File(picked.path).readAsBytes();
    if (!mounted) return;

    setState(() => _promptTask = _PromptTask.describe);
    final result = await (engine as ImageToTextCapable).describeImage(bytes);
    if (!mounted) return;
    setState(() => _promptTask = null);
    result.fold(
      (description) {
        final current = _prompt.text.trim();
        if (current.isNotEmpty) _rt.promptBook.record(current);
        _setPrompt(description);
        _notify('Described the input image.');
      },
      (error) => _notify(error.message, isError: true),
    );
  }

  // ===== Canvas editors ===== //

  /// Decodes the session's source image once, for whichever editor needs it.
  /// Both the mask painter and the outpaint view work in image coordinates,
  /// so they need real pixel dimensions rather than the on-screen size.
  Future<ui.Image?> _decodeSource() async {
    final file = _rt.session.state.sourceImage;
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return await decodeImageFromList(bytes);
    } catch (e) {
      if (mounted) _notify('Could not read the source image: $e', isError: true);
      return null;
    }
  }

  Future<void> _openMaskEditor() async {
    final file = _rt.session.state.sourceImage;
    final decoded = await _decodeSource();
    if (!mounted || decoded == null || file == null) return;

    final result = await Navigator.of(context).push<MaskResult?>(
      DeskPageRoute(
        builder: (_) => MaskEditor(
          image: decoded,
          display: FileImage(file),
          // Reopening on the existing strokes rather than a blank canvas:
          // a mask is careful work, and coming back to adjust one corner
          // should not mean painting the other three again.
          initial: _rt.session.state.maskDraft,
        ),
        fullscreenDialog: true,
      ),
    );
    decoded.dispose();
    if (!mounted) return;

    // A null result means "cancelled, or opened empty and left empty". Both
    // should leave any existing mask alone rather than silently dropping it.
    if (result == null) return;
    final bytes = result.bytes;
    if (bytes == null) {
      _rt.session.setMask(null);
      _notify('Mask cleared.');
      return;
    }
    _rt.session.setMask(bytes, draft: result.draft);
    setState(() => _viewingId = _kInputId);
    _notify('Mask applied. Generating will inpaint the painted area.');
  }

  Future<void> _openOutpaintEditor() async {
    final file = _rt.session.state.sourceImage;
    final decoded = await _decodeSource();
    if (!mounted || decoded == null || file == null) return;

    final result = await Navigator.of(context).push<OutpaintResult?>(
      DeskPageRoute(
        builder: (_) => OutpaintEditor(image: decoded, display: FileImage(file)),
        fullscreenDialog: true,
      ),
    );
    decoded.dispose();
    if (!mounted || result == null) return;

    try {
      final dir = await getTemporaryDirectory();
      final expanded = File(
          '${dir.path}/aperture_extended_${DateTime.now().millisecondsSinceEpoch}.png');
      await expanded.writeAsBytes(result.image);
      if (!mounted) return;
      // Order matters: setSourceImage deliberately clears the mask, so the
      // outpaint mask has to be applied after the enlarged image, not before.
      _rt.session.setSourceImage(expanded);
      _rt.session.setMask(result.mask);
      setState(() => _viewingId = _kInputId);
      _notify('Canvas extended. Generating will fill the new area.');
    } catch (e) {
      if (mounted) _notify('Could not extend the canvas: $e', isError: true);
    }
  }

  // ===== Result tools ===== //

  bool get _viewingInput => _viewingId == _kInputId;

  GeneratedImage? _focusedImage(LibraryState library) {
    final id = _viewingId;
    if (id == null || id == _kInputId) return null;
    for (final image in library.images) {
      if (image.id == id) return image;
    }
    return null;
  }

  /// Tapping the input card: pick one if there isn't one yet, otherwise
  /// promote it to the main display like any other card on the shelf.
  void _onInputTapped() {
    if (!_rt.session.state.hasSourceImage) {
      _pickSourceImage();
      return;
    }
    setState(() => _viewingId = _kInputId);
  }

  Future<Uint8List?> _imageBytes(GeneratedImage image) async {
    if (image.isDataUrl) {
      return base64Decode(image.url.substring(image.url.indexOf(',') + 1));
    }
    final result = await _rt.activeEngine.fetchImageBytes(image.url);
    return result.fold((bytes) => bytes, (_) => null);
  }

  /// CHECKLIST 5.1: save to the device's own photo library.
  ///
  /// Writing to a path directly stopped being viable on Android 10+ scoped
  /// storage - an app can only publish to shared media through MediaStore,
  /// which is what `gal` wraps. The earlier version wrote into the app's
  /// private external directory, which "worked" but put the file somewhere
  /// the gallery never looks.
  Future<void> _saveFocused(LibraryState library) async {
    final image = _focusedImage(library);
    if (image == null) return;

    final bytes = await _imageBytes(image);
    if (!mounted) return;
    if (bytes == null) {
      _notify('Could not read that image.', isError: true);
      return;
    }

    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!mounted) return;
        if (!granted) {
          _notify('Photo library access was declined, so nothing was saved.',
              isError: true);
          return;
        }
      }
      await Gal.putImageBytes(bytes, album: 'Aperture');
      if (mounted) _notify('Saved to your photo library, in "Aperture".');
    } on GalException catch (e) {
      if (mounted) _notify('Save failed: ${e.type.message}', isError: true);
    } catch (e) {
      if (mounted) _notify('Save failed: $e', isError: true);
    }
  }

  /// Upscaling is offered for the source image as well as for results - a
  /// small input is exactly the case where upscaling before an img2img run
  /// is worth doing, and the engine does not care which it was.
  Future<void> _openUpscaleDrawer(LibraryState library) async {
    final capabilities = _rt.engine.state.capabilities;
    if (!capabilities.upscale) {
      _notify('Upscaling is not supported by this engine.', isError: true);
      return;
    }
    final target = await _activeImageBytes(library);
    if (!mounted || target == null) {
      if (mounted) _notify('Could not read that image.', isError: true);
      return;
    }
    final size = readPngDimensions(target.$1);

    await showDeskDrawer<void>(
      context: context,
      title: 'Upscale',
      builder: (context) {
        final p = DeskTheme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (size != null) ...[
              Text('CURRENT', style: Type.micro.copyWith(color: p.inkFaint)),
              const SizedBox(height: 2),
              Text('${size.$1} × ${size.$2}',
                  style: Type.readout.copyWith(color: p.ink, fontSize: 14)),
              const SizedBox(height: Space.lg),
            ],
            Text('TARGET LONGEST SIDE',
                style: Type.micro.copyWith(color: p.inkFaint)),
            const SizedBox(height: Space.sm),
            for (final resolution in const [1024, 2048, 3072, 4096])
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: DeskButton(
                  label: '$resolution px',
                  icon: Icons.zoom_in_rounded,
                  expand: true,
                  onPressed: () {
                    Navigator.of(context).pop();
                    _runUpscale(target.$1, resolution);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// Upscaling is a generation in every way that matters: it occupies the
  /// engine, it takes real time, it streams progress, and it **produces a
  /// new image**. So it drives the same progress bar as a run (labelled
  /// "UPSCALING"), and its output always lands as a new print - it never
  /// overwrites what it was made from, which would destroy the only copy of
  /// the original and make the two impossible to compare.
  Future<void> _runUpscale(Uint8List bytes, int resolution) async {
    if (_rt.run.isActive) {
      _notify('Something is already running.', isError: true);
      return;
    }
    final baseEngine = _rt.activeEngine;
    if (baseEngine is! UpscaleCapable) {
      _notify('Upscaling is not supported by this engine.', isError: true);
      return;
    }

    _rt.run.beginTask('Upscaling');
    setState(() => _viewingId = null);

    final result = await (baseEngine as UpscaleCapable).upscale(
      image: bytes,
      targetResolution: resolution,
      // Stamp every frame with the label, so the bar says what it is doing
      // rather than inheriting the engine's generic phase name.
      onProgress: (progress) =>
          _rt.run.report(progress.copyWith(stage: 'Upscaling')),
    );
    if (!mounted) return;

    result.fold(
      (url) {
        _rt.library.add([GeneratedImage.fromTool(url, baseEngine.kind)]);
        _rt.run.succeed();
        setState(() => _viewingId = _rt.library.state.selectedId);
      },
      (error) {
        _rt.run.fail(error);
        _notify(error.message, isError: true);
      },
    );
  }

  /// CHECKLIST 2.4: send a result back to the canvas. The session holds a
  /// `File`, so the bytes are spooled to a cache file first - ComfyUI hands
  /// back a URL and Forge a data URL, and neither is a file on disk.
  Future<void> _sendResultToInput(LibraryState library) async {
    final image = _focusedImage(library);
    if (image == null) return;
    final bytes = await _imageBytes(image);
    if (!mounted) return;
    if (bytes == null) {
      _notify('Could not read that image.', isError: true);
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/aperture_input_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      _rt.session.setSourceImage(file);
      setState(() => _viewingId = _kInputId);
      _notify('Sent to input. Generate to work from it.');
    } catch (e) {
      if (mounted) _notify('Could not send to input: $e', isError: true);
    }
  }

  Future<void> _confirmDeleteFocused(LibraryState library) async {
    final id = _viewingId;
    if (id == null || id == _kInputId) return;
    final confirmed = await showDeskDrawer<bool>(
      context: context,
      title: 'Delete this print?',
      builder: (context) {
        final p = DeskTheme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "This removes it from your session. If you haven't saved it, it's gone.",
              style: Type.body.copyWith(color: p.inkFaint),
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: DeskButton(
                    label: 'Cancel',
                    kind: DeskButtonKind.secondary,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: DeskButton(
                    label: 'Delete',
                    kind: DeskButtonKind.destructive,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _rt.library.remove(id);
      if (mounted) setState(() => _viewingId = null);
    }
  }

  // ===== Drawers ===== //

  Future<void> _openServerDrawer() => showDeskDrawer<void>(
        context: context,
        title: 'Server',
        action: ValueListenableBuilder<EngineState>(
          valueListenable: _rt.engine,
          builder: (context, s, _) =>
              DeskStamp(label: s.status.label, color: _statusColor(s.status)),
        ),
        builder: (context) => _EngineDrawerContent(
          engineState: _rt.engine.state,
          onConnect: (kind, endpoint) => _connect(kind, withEndpoint: endpoint),
        ),
      );

  Future<void> _openWorkflowsDrawer(ComfyWorkflowService workflows) => showDeskDrawer<void>(
        context: context,
        title: 'Workflows',
        action: DeskButton(
          label: 'Add',
          icon: Icons.add_rounded,
          kind: DeskButtonKind.secondary,
          onPressed: () => _importWorkflow(workflows),
        ),
        builder: (context) => _WorkflowsDrawerContent(
          workflows: workflows,
          onSelect: (record) => _selectWorkflow(workflows, record),
          onManage: (record) => _openWorkflowActions(workflows, record),
        ),
      );

  /// Switching workflow can silently invalidate a painted mask: a mask only
  /// means anything to an inpainting graph, and every other type ignores it.
  /// Losing careful masking work without being asked is the kind of thing
  /// that is only noticed after the run comes back wrong, so confirm first.
  Future<void> _selectWorkflow(
    ComfyWorkflowService workflows,
    ComfyWorkflowRecord record,
  ) async {
    final hasMask = _rt.session.state.mask != null;
    final leavingInpaint = record.workflowType != ComfyWorkflowType.inpainting;

    if (hasMask && leavingInpaint) {
      final confirmed = await showDeskDrawer<bool>(
        context: context,
        title: 'Discard your mask?',
        builder: (context) {
          final p = DeskTheme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '"${record.name}" is a ${record.workflowType.displayName.toLowerCase()} '
                'workflow, which ignores masks. Switching to it drops the mask '
                'you painted.',
                style: Type.body.copyWith(color: p.inkFaint),
              ),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(
                    child: DeskButton(
                      label: 'Keep masking',
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: DeskButton(
                      label: 'Switch anyway',
                      kind: DeskButtonKind.destructive,
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      _rt.session.setMask(null);
    }

    await workflows.selectWorkflow(record.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Per-workflow management, reached from the ⋮ on its row. Everything here
  /// already existed on `ComfyWorkflowService` and simply had no UI.
  Future<void> _openWorkflowActions(
    ComfyWorkflowService workflows,
    ComfyWorkflowRecord record,
  ) =>
      showDeskDrawer<void>(
        context: context,
        title: record.name,
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DeskButton(
              label: 'Edit settings',
              icon: Icons.tune_rounded,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                _openWorkflowSettingsDrawer(workflows, record);
              },
            ),
            const SizedBox(height: Space.sm),
            DeskButton(
              label: 'Rename',
              icon: Icons.edit_rounded,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                _renameWorkflow(workflows, record);
              },
            ),
            const SizedBox(height: Space.sm),
            DeskButton(
              label: 'Change type',
              icon: Icons.category_rounded,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                _changeWorkflowType(workflows, record);
              },
            ),
            const SizedBox(height: Space.sm),
            DeskButton(
              label: 'Duplicate',
              icon: Icons.copy_rounded,
              expand: true,
              onPressed: () async {
                Navigator.of(context).pop();
                await workflows.duplicateWorkflow(record.id);
                if (mounted) _notify('Duplicated ${record.name}');
              },
            ),
            const SizedBox(height: Space.lg),
            DeskButton(
              label: 'Delete',
              icon: Icons.delete_outline_rounded,
              kind: DeskButtonKind.destructive,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                _confirmDeleteWorkflow(workflows, record);
              },
            ),
          ],
        ),
      );

  Future<void> _openWorkflowSettingsDrawer(
    ComfyWorkflowService workflows,
    ComfyWorkflowRecord record,
  ) async {
    // Editing a workflow's settings only makes sense against the analysed
    // graph, and only the *active* workflow is analysed - so select it first.
    if (workflows.activeWorkflowId.value != record.id) {
      await workflows.selectWorkflow(record.id);
    }
    if (!mounted) return;
    await openWorkflowSettings(
      context,
      workflows: workflows,
      library: _rt.engines.modelLibraryFor(_rt.engine.state.endpoint),
      title: record.name,
    );
  }

  Future<void> _renameWorkflow(
    ComfyWorkflowService workflows,
    ComfyWorkflowRecord record,
  ) async {
    final controller = TextEditingController(text: record.name);
    final name = await showDeskDrawer<String>(
      context: context,
      title: 'Rename workflow',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DeskField(label: 'Name', controller: controller),
          const SizedBox(height: Space.lg),
          DeskButton(
            label: 'Save',
            kind: DeskButtonKind.primary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await workflows.renameWorkflow(record.id, name);
  }

  Future<void> _changeWorkflowType(
    ComfyWorkflowService workflows,
    ComfyWorkflowRecord record,
  ) async {
    final picked = await showDeskDrawer<ComfyWorkflowType>(
      context: context,
      title: 'Workflow type',
      builder: (context) {
        final p = DeskTheme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in ComfyWorkflowType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(type),
                  child: Container(
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      color: p.paper,
                      borderRadius: BorderRadius.circular(Corner.control),
                      border: Border.all(
                        color: type == record.workflowType ? p.clay : p.ink,
                        width: type == record.workflowType
                            ? Stroke.live
                            : Stroke.standard,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type.displayName,
                            style: Type.label.copyWith(color: p.ink)),
                        const SizedBox(height: 2),
                        Text(type.description,
                            style: Type.body.copyWith(color: p.inkFaint)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (picked == null) return;
    await workflows.setWorkflowType(record.id, picked);
  }

  Future<void> _confirmDeleteWorkflow(
    ComfyWorkflowService workflows,
    ComfyWorkflowRecord record,
  ) async {
    final confirmed = await showDeskDrawer<bool>(
      context: context,
      title: 'Delete ${record.name}?',
      builder: (context) {
        final p = DeskTheme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This removes the workflow and its saved settings from this '
              'server. The original .json file on your device is untouched.',
              style: Type.body.copyWith(color: p.inkFaint),
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: DeskButton(
                    label: 'Cancel',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: DeskButton(
                    label: 'Delete',
                    kind: DeskButtonKind.destructive,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await workflows.deleteWorkflow(record.id);
      if (mounted) _notify('Deleted ${record.name}');
    }
  }

  Future<void> _importWorkflow(ComfyWorkflowService workflows) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) _notify('Could not read that file.', isError: true);
      return;
    }

    final defaultName = file.name.replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
    if (!mounted) return;
    final choice = await Navigator.of(context).push<_ImportChoice>(
      DeskPageRoute(
        builder: (_) => _ImportWorkflowSheet(defaultName: defaultName),
        fullscreenDialog: true,
      ),
    );
    if (choice == null || !mounted) return;

    try {
      final record = await workflows.importWorkflow(
        utf8.decode(bytes),
        name: choice.name,
        workflowType: choice.type,
      );
      await workflows.selectWorkflow(record.id);
      if (mounted) Navigator.of(context).pop(); // close the Workflows drawer
    } catch (e) {
      if (mounted) _notify('Import failed: $e', isError: true);
    }
  }

  /// Forge's equivalent of the Workflows drawer: pick which checkpoint the
  /// server should load. Applying it server-side is slow (Forge only swaps
  /// weights when something needs them), so this reports progress and stays
  /// open until the swap lands.
  Future<void> _openCheckpointDrawer() => showDeskDrawer<void>(
        context: context,
        title: 'Checkpoints',
        action: DeskButton(
          label: 'Refresh',
          icon: Icons.refresh_rounded,
          onPressed: () => _refreshCheckpoints(force: true),
        ),
        builder: (context) => ValueListenableBuilder<CatalogState>(
          valueListenable: _rt.catalog,
          builder: (context, catalog, _) {
            final p = DeskTheme.of(context);
            if (catalog.isLoading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.xxl),
                child: Center(child: DeskProgress(caption: 'LOADING CHECKPOINTS')),
              );
            }
            if (catalog.checkpoints.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxl),
                child: Center(
                  child: Text(
                    'No checkpoints found on this server.\nTap Refresh to rescan.',
                    textAlign: TextAlign.center,
                    style: Type.body.copyWith(color: p.inkFaint),
                  ),
                ),
              );
            }
            // Grouped by base model, which is what `CatalogState.byBaseModel`
            // already exists to provide.
            final groups = catalog.byBaseModel;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, Space.md, 0, Space.sm),
                    child: Text(entry.key.toUpperCase(),
                        style: Type.micro.copyWith(color: p.inkFaint)),
                  ),
                  for (final checkpoint in entry.value)
                    _CheckpointRow(
                      checkpoint: checkpoint,
                      selected: checkpoint.name == catalog.activeCheckpoint,
                      onTap: () {
                        Navigator.of(context).pop();
                        _applyCheckpoint(checkpoint);
                      },
                    ),
                ],
              ],
            );
          },
        ),
      );

  Future<void> _refreshCheckpoints({bool force = false}) async {
    final endpoint = _rt.engine.state.endpoints[EngineKind.forge]!;
    _rt.catalog.setLoading(true);
    final result =
        await ForgeCatalogClient(endpoint: endpoint).fetchCheckpoints(force: force);
    if (!mounted) return;
    result.fold(
      _rt.catalog.setCheckpoints,
      (error) {
        _rt.catalog.setLoading(false);
        _notify(error.message, isError: true);
      },
    );
  }

  Future<void> _applyCheckpoint(Checkpoint checkpoint) async {
    final endpoint = _rt.engine.state.endpoints[EngineKind.forge]!;
    _rt.catalog.selectCheckpoint(checkpoint.name);

    // 3.4: a checkpoint carries the sampling settings it likes. Applying
    // them on switch is the whole reason `Checkpoint.defaults` exists -
    // without this the field was dead weight.
    if (checkpoint.defaults != const SamplingParams()) {
      _rt.session.setSampling(checkpoint.defaults);
    }

    _notify('Loading ${checkpoint.name}…');
    final result = await ForgeCatalogClient(endpoint: endpoint)
        .selectCheckpointAndWait(checkpoint);
    if (!mounted) return;
    result.fold(
      (_) => _notify('${checkpoint.name} loaded'),
      (error) => _notify(error.message, isError: true),
    );
  }

  /// ComfyUI's generation settings live in the workflow graph, not in
  /// `SamplingParams` - the graph is what actually gets executed, and it is
  /// what persists per workflow. Forge has no graph, so it keeps the
  /// session-level params drawer.
  Future<void> _openSettingsDrawer() {
    final engineState = _rt.engine.state;
    if (engineState.active == EngineKind.comfy) {
      final workflows = _rt.engines.workflowsFor(engineState.endpoint);
      final record = workflows.activeRecord;
      if (record == null) {
        _notify('Pick a workflow first - its settings come from the graph.');
        return Future.value();
      }
      return openWorkflowSettings(
        context,
        workflows: workflows,
        library: _rt.engines.modelLibraryFor(engineState.endpoint),
        title: record.name,
      );
    }
    return _openForgeSettingsDrawer();
  }

  Future<void> _openForgeSettingsDrawer() => showDeskDrawer<void>(
        context: context,
        title: 'Generation settings',
        builder: (context) => ValueListenableBuilder<SessionState>(
          valueListenable: _rt.session,
          builder: (context, s, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeskRuler(
                label: 'Steps',
                value: s.sampling.steps.toDouble(),
                min: 1,
                max: 60,
                divisions: 59,
                format: (v) => v.round().toString(),
                onChanged: (v) =>
                    _rt.session.tuneSampling((p) => p.copyWith(steps: v.round())),
              ),
              const SizedBox(height: Space.lg),
              DeskRuler(
                label: 'Guidance',
                value: s.sampling.cfgScale,
                min: 1,
                max: 15,
                format: (v) => v.toStringAsFixed(2),
                onChanged: (v) =>
                    _rt.session.tuneSampling((p) => p.copyWith(cfgScale: v)),
              ),
              const SizedBox(height: Space.lg),
              DeskDropdown<int>(
                label: 'Resolution',
                value: s.sampling.width,
                options: const [
                  DeskOption(value: 512, label: '512 × 512'),
                  DeskOption(value: 768, label: '768 × 768', detail: 'DEFAULT'),
                  DeskOption(value: 1024, label: '1024 × 1024'),
                ],
                onChanged: (v) =>
                    _rt.session.tuneSampling((p) => p.copyWith(width: v, height: v)),
              ),
              const SizedBox(height: Space.lg),
              DeskRuler(
                label: 'Batch size',
                value: s.sampling.batchSize.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                format: (v) => v.round().toString(),
                onChanged: (v) => _rt.session
                    .tuneSampling((p) => p.copyWith(batchSize: v.round())),
              ),
              const SizedBox(height: Space.lg),
              DeskDropdown<String>(
                label: 'Sampler',
                value: s.sampling.sampler,
                options: [
                  for (final name in samplerNames)
                    DeskOption(value: name, label: name),
                ],
                onChanged: (v) =>
                    _rt.session.tuneSampling((p) => p.copyWith(sampler: v)),
              ),
              const SizedBox(height: Space.lg),
              DeskDropdown<String>(
                label: 'Scheduler',
                value: s.sampling.scheduler,
                options: [
                  for (final name in schedulerNames)
                    DeskOption(value: name, label: name),
                ],
                onChanged: (v) =>
                    _rt.session.tuneSampling((p) => p.copyWith(scheduler: v)),
              ),

              // Denoise only means anything once there's a source image to
              // denoise *from* - on a pure txt2img run it is ignored, so
              // showing it would just be a control that does nothing.
              if (s.hasSourceImage) ...[
                const SizedBox(height: Space.lg),
                DeskRuler(
                  label: 'Denoise',
                  value: s.sampling.denoise,
                  min: 0,
                  max: 1,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) =>
                      _rt.session.tuneSampling((p) => p.copyWith(denoise: v)),
                ),
              ],

              // Mask settings likewise: they only apply to an inpaint run.
              if (s.mode == GenerationMode.inpaint) ...[
                const SizedBox(height: Space.lg),
                DeskRuler(
                  label: 'Mask blur',
                  value: s.sampling.maskBlur.toDouble(),
                  min: 0,
                  max: 64,
                  divisions: 64,
                  format: (v) => '${v.round()} px',
                  onChanged: (v) => _rt.session
                      .tuneSampling((p) => p.copyWith(maskBlur: v.round())),
                ),
                const SizedBox(height: Space.lg),
                DeskDropdown<MaskFill>(
                  label: 'Masked content',
                  value: s.sampling.maskFill,
                  options: [
                    for (final fill in MaskFill.values)
                      DeskOption(value: fill, label: fill.label),
                  ],
                  onChanged: (v) =>
                      _rt.session.tuneSampling((p) => p.copyWith(maskFill: v)),
                ),
              ],

              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Random seed',
                      style: Type.label.copyWith(color: DeskTheme.of(context).ink),
                    ),
                  ),
                  DeskToggle(
                    value: s.sampling.isSeedRandom,
                    onChanged: (random) => _rt.session.tuneSampling(
                      (p) => random
                          ? p.copyWith(clearSeed: true)
                          : p.copyWith(seed: DateTime.now().millisecondsSinceEpoch % 4294967296),
                    ),
                  ),
                ],
              ),
              if (!s.sampling.isSeedRandom) ...[
                const SizedBox(height: Space.md),
                Text(
                  'SEED ${s.sampling.seed}',
                  style: Type.readout.copyWith(color: DeskTheme.of(context).inkFaint),
                ),
              ],
            ],
          ),
        ),
      );

  // ===== Sticky note toasts ===== //

  void _notify(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    final palette = DeskTheme.of(context);
    final mode = DeskTheme.modeOf(context);
    late final OverlayEntry entry;
    var dismissed = false;
    void dismiss() {
      if (dismissed) return;
      dismissed = true;
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + Space.md,
        right: Space.gutter,
        child: DeskTheme(
          palette: palette,
          mode: mode,
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: StickyNote(message: message, isError: isError, onDismiss: dismiss),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 4), dismiss);
  }

  // ===== Build ===== //

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Desk(
      mode: brightness == Brightness.dark ? DeskMode.night : DeskMode.day,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // The keyboard must not resize the body. Letting it shrink the
        // Column re-ran the canvas's layout every frame the keyboard
        // animated, which is the "weird image resize" - the picture visibly
        // rescaled as the prompt came up. Instead the whole page slides, so
        // nothing re-lays-out and nothing re-decodes.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          // Tapping anywhere that isn't itself an interactive control drops
          // focus, so the keyboard actually goes away.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: AnimatedSlide(
              // Travel in fractions of the page, so the composer clears the
              // keyboard without the layout above it changing size at all.
              offset: Offset(0, -_keyboardSlide(context)),
              duration: Motion.fade,
              curve: Motion.ease,
              child: AnimatedBuilder(
              animation: _stores,
              builder: (context, _) {
                final engineState = _rt.engine.state;
                if (engineState.active == EngineKind.comfy) {
                  final workflows = _rt.engines.workflowsFor(engineState.endpoint);
                  return AnimatedBuilder(
                    animation: Listenable.merge([
                      workflows.workflows,
                      workflows.activeWorkflowId,
                      workflows.activeDetected,
                      workflows.activeError,
                    ]),
                    builder: (context, _) => _buildBody(context, workflows),
                  );
                }
                return _buildBody(context, null);
              },
            ),
            ),
          ),
        ),
      ),
    );
  }

  /// How far to lift the page so the prompt clears the keyboard, as a
  /// fraction of the page height. Capped, because sliding the whole page off
  /// the top to chase a very tall keyboard is worse than a partial view.
  double _keyboardSlide(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset <= 0) return 0;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return 0;
    final fraction = inset / height;
    return fraction > 0.32 ? 0.32 : fraction;
  }

  Widget _buildBody(BuildContext context, ComfyWorkflowService? workflows) {
    final p = DeskTheme.of(context);
    final engineState = _rt.engine.state;
    final session = _rt.session.state;
    final run = _rt.run.state;
    final library = _rt.library.state;
    final catalog = _rt.catalog.state;
    final capabilities = engineState.capabilities;

    final focused = _focusedImage(library);
    final viewingResult = focused != null && !run.isActive;
    // The tray always describes whatever the main display is showing.
    final tools = run.isActive
        ? _trayTools(capabilities, session.mode)
        : viewingResult
            ? _resultTools(capabilities, library)
            : (_viewingInput && session.hasSourceImage)
                ? _inputTools()
                : _trayTools(capabilities, session.mode);
    final ready = _isReady(engineState, workflows) && session.hasPrompt && !run.isActive;
    final shelfEntries = _shelfEntries(run, library);
    final inputEntry = _inputEntry(context, engineState, session, workflows);

    return Column(
      children: [
        Padding(
          key: const ValueKey('title'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
          child: _titleRow(context, engineState, catalog, workflows),
        ),

        // ===== Tray + main display ===== //
        Expanded(
          key: const ValueKey('canvas'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // No activeIndex: every tool here is a one-shot action, so
                // there is no "current tool" to show. Carrying the last tap
                // as a selection made an unrelated icon look armed while the
                // user was just moving between images.
                DeskToolTray(tools: tools),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                          child: _mainDisplay(context, session, run, focused)),
                      // On the canvas rather than in the tray: this is a
                      // gesture *about the picture*, and holding a button at
                      // the far edge while watching the middle of the image
                      // is an awkward reach.
                      if (session.hasSourceImage && !run.isActive && focused != null)
                        Positioned(
                          right: Space.md,
                          bottom: Space.md,
                          child: _CompareButton(
                            onHoldChanged: (held) =>
                                setState(() => _comparing = held),
                          ),
                        ),

                    ],
                  ),
                ),
                const SizedBox(width: Space.gutter),
              ],
            ),
          ),
        ),

        // ===== The shelf: source image, divider, then every result. Shows
        // an empty, shimmering print per batch slot from the moment a run is
        // queued, per DESIGN.md 7.14. ===== //
        Padding(
          key: const ValueKey('shelf'),
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: (shelfEntries.isEmpty && inputEntry == null)
              ? SizedBox(
                  height: 110,
                  child: Center(
                    child: Text('NOTHING PRINTED YET',
                        style: Type.micro.copyWith(color: p.inkFaint)),
                  ),
                )
              : PrintShelf(
                  input: inputEntry,
                  selectedId: _viewingId ?? library.selectedId,
                  onSelect: (id) {
                    if (id == _kInputId) {
                      _onInputTapped();
                      return;
                    }
                    if (id == _kRunId) {
                      setState(() => _viewingId = _kRunId);
                      return;
                    }
                    _rt.library.select(id);
                    if (library.images.any((i) => i.id == id)) {
                      setState(() => _viewingId = id);
                    }
                  },
                  entries: shelfEntries,
                ),
        ),

        // ===== Progress, only while a run is in flight ===== //
        if (run.isActive)
          Padding(
            key: const ValueKey('progress'),
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
            child: DeskProgress(
              fraction: run.progress.fraction,
              caption: _progressCaption(run.progress),
            ),
          ),

        // ===== Prompt, status, generate ===== //
        Padding(
          key: const ValueKey('composer'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeskField(
                label: 'Prompt',
                controller: _prompt,
                maxLines: 2,
                onChanged: _rt.session.setPrompt,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Appears once there is something to go back to: an
                    // accidental clear, or an enhancement/description that
                    // turned out worse than what it replaced.
                    if (_promptUndo != null && _promptUndo != session.prompt)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _undoPrompt,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm, vertical: 2),
                          child: Icon(Icons.undo_rounded,
                              size: 14, color: p.inkMuted),
                        ),
                      ),
                    // Only offered when there is something to clear, so the
                    // label row stays quiet on an empty prompt.
                    if (session.prompt.trim().isNotEmpty)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setPrompt(''),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm, vertical: 2),
                          child: Icon(Icons.backspace_outlined,
                              size: 13, color: p.inkMuted),
                        ),
                      ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openPromptEditor,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm, vertical: 2),
                        child: Icon(Icons.open_in_full_rounded,
                            size: 14, color: p.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
              // Prompt actions sit with the prompt, not in the tray - they
              // act on the text, and every one of them is capability-gated
              // so an engine never advertises what it cannot do.
              Row(
                children: [
                  _PromptAction(
                    icon: Icons.history_rounded,
                    label: 'Prompts',
                    onTap: _promptBusy ? null : _openPromptBook,
                  ),
                  // One button, two tools. Holding it swaps which - they do
                  // the same job from opposite ends (rewrite what is there,
                  // or write something when nothing is), and a fourth button
                  // in this row would not fit a phone.
                  if (capabilities.promptRewrite ||
                      capabilities.promptGenerate) ...[
                    const SizedBox(width: Space.sm),
                    _PromptAction(
                      icon: _generating
                          ? Icons.casino_rounded
                          : Icons.auto_awesome_rounded,
                      // "Write", not "Generate": the button that starts a
                      // run is already called that, and two Generates in one
                      // screen is a coin toss every time.
                      label: _generating ? 'Write' : 'Enhance',
                      busy: _promptTask == _PromptTask.enhance ||
                          _promptTask == _PromptTask.generate,
                      onTap: _promptBusy
                          ? null
                          : (_generating ? _generatePrompt : _enhancePrompt),
                      onLongPress: capabilities.promptGenerate &&
                              capabilities.promptRewrite
                          ? _togglePromptTool
                          : null,
                    ),
                  ],
                  // Describe picks its own image, so it does not depend on
                  // there being a source loaded - which is what lets it be
                  // used to start a txt2img prompt from a photo.
                  if (capabilities.imageToText) ...[
                    const SizedBox(width: Space.sm),
                    _PromptAction(
                      icon: Icons.image_search_rounded,
                      label: 'Describe',
                      busy: _promptTask == _PromptTask.describe,
                      onTap: _promptBusy ? null : _describeImage,
                    ),
                  ],
                ],
              ),
              // Only while the writer is armed. It is the one input that
              // tool takes, and a dial for a button that is not on screen
              // would be furniture.
              if (_generating) ...[
                const SizedBox(height: Space.md),
                DeskTape(
                  label: 'Intensity',
                  value: _promptIntensity,
                  min: 1,
                  max: 10,
                  steps: const [1],
                  format: (v) => v.round().toString(),
                  onChanged: (v) => setState(() => _promptIntensity = v),
                ),
              ],
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _statusText(engineState, run),
                      style: Type.micro.copyWith(color: p.inkFaint),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  if (run.isActive)
                    DeskButton(
                      label: 'Stop',
                      kind: DeskButtonKind.destructive,
                      onPressed: _rt.cancelRun,
                    )
                  else ...[
                    // Upscale sits beside Generate because it is the same
                    // kind of act - it occupies the engine and produces a
                    // new print - rather than an edit to the image on screen.
                    if (capabilities.upscale &&
                        (focused != null || session.hasSourceImage))
                      Padding(
                        padding: const EdgeInsets.only(right: Space.sm),
                        child: DeskButton(
                          label: 'Upscale',
                          icon: Icons.zoom_in_rounded,
                          onPressed: () => _openUpscaleDrawer(library),
                        ),
                      ),
                    DeskButton(
                      label: 'Generate',
                      icon: Icons.play_arrow_rounded,
                      kind: DeskButtonKind.primary,
                      onPressed: ready ? _generate : null,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _titleRow(
    BuildContext context,
    EngineState engineState,
    CatalogState catalog,
    ComfyWorkflowService? workflows,
  ) {
    final p = DeskTheme.of(context);
    final loraCount = catalog.activeLoras.length;

    return Row(
      children: [
        _engineBadge(context, engineState),
        const SizedBox(width: Space.sm),
        Expanded(
          child: _workflowSelector(
            context,
            label: _selectorLabel(engineState, catalog, workflows),
            onTap: engineState.active == EngineKind.comfy
                ? (workflows != null
                    ? () => _openWorkflowsDrawer(workflows)
                    : _openServerDrawer)
                : _openCheckpointDrawer,
          ),
        ),
        const SizedBox(width: Space.sm),
        // Browsing other people's work is engine-independent, so unlike the
        // server gallery this is never capability-gated.
        _titleAction(p, Icons.travel_explore_rounded, _openCivitai),
        if (engineState.capabilities.serverLibrary) ...[
          const SizedBox(width: Space.sm),
          // Not a tray tool: the tray acts on the image on the canvas, and
          // browsing history is neither an edit nor a canvas action.
          _titleAction(p, Icons.photo_library_rounded, _openGallery),
        ],
        if (engineState.capabilities.loras && loraCount > 0) ...[
          const SizedBox(width: Space.sm),
          DeskCard(label: '$loraCount lora${loraCount == 1 ? '' : 's'}'),
        ],
      ],
    );
  }

  /// A square icon control for the title row.
  Widget _titleAction(DeskPalette p, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(Corner.control),
            border: Border.all(color: p.ink, width: Stroke.standard),
            boxShadow: Elevation.rest.shadows(p.ink),
          ),
          child: Icon(icon, size: 18, color: p.ink),
        ),
      );

  /// Browse Civitai and bring a prompt back.
  ///
  /// The page returns the prompt rather than writing it itself, so the one
  /// place that owns the prompt field stays the one place that sets it - and
  /// the previous prompt is recorded first, so taking someone else's is not
  /// a one-way door.
  Future<void> _openCivitai() async {
    final pick = await Navigator.of(context).push<CivitaiPick>(
      DeskPageRoute(builder: (_) => const CivitaiPage()),
    );
    if (pick == null || !mounted) return;

    final current = _prompt.text.trim();
    if (current.isNotEmpty) _rt.promptBook.record(current);
    _setPrompt(pick.prompt);
    if (pick.negativePrompt != null && pick.negativePrompt!.isNotEmpty) {
      _rt.session.setNegativePrompt(pick.negativePrompt!);
    }
    _notify(pick.negativePrompt == null
        ? 'Prompt taken from Civitai.'
        : 'Prompt and negative prompt taken from Civitai.');
  }

  /// Engine identity and connection status, merged into one control instead
  /// of a card plus a separate stamp - tapping opens the Server drawer,
  /// which is also where you switch engines.
  Widget _engineBadge(BuildContext context, EngineState engineState) {
    final p = DeskTheme.of(context);
    final color = _connecting ? DeskPalette.caution : _statusColor(engineState.status);
    return GestureDetector(
      onTap: _openServerDrawer,
      onLongPress: kDebugMode
          ? () => Navigator.of(context)
              .push(DeskPageRoute(builder: (_) => const DevHarness()))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: p.ink,
          borderRadius: BorderRadius.circular(Corner.photo),
          border: Border.all(color: color, width: Stroke.standard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(engineState.active.label.toUpperCase(),
                style: Type.micro.copyWith(color: p.paper)),
          ],
        ),
      ),
    );
  }

  /// The rest of the title row: whatever is loaded (checkpoint or workflow),
  /// doubling as the single opener for picking a different one.
  Widget _workflowSelector(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final p = DeskTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(Corner.control),
          border: Border.all(color: p.ink, width: Stroke.standard),
          boxShadow: Elevation.rest.shadows(p.ink),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Type.label.copyWith(color: p.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: p.inkMuted),
          ],
        ),
      ),
    );
  }

  /// The source image's card on the shelf, left of the divider. Present only
  /// when there's a reason for it: an img2img/inpaint ComfyUI workflow, a
  /// Forge session (which has no workflow-type declaration and so always
  /// offers one), or a leftover source image from before a workflow switch.
  /// A txt2img workflow gets no input card at all.
  PrintEntry? _inputEntry(
    BuildContext context,
    EngineState engineState,
    SessionState session,
    ComfyWorkflowService? workflows,
  ) {
    final needsInput = engineState.active == EngineKind.forge
        ? true
        : (workflows?.activeRecord?.workflowType.needsInputImage ?? false);
    if (!needsInput && !session.hasSourceImage) return null;

    final p = DeskTheme.of(context);
    return PrintEntry(
      id: _kInputId,
      // Double-tap goes straight to the picker, so replacing the source is
      // one gesture on the card itself rather than select-then-find-the-tool.
      onDoubleTap: _pickSourceImage,
      image: session.sourceImage != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.file(session.sourceImage!,
                    fit: BoxFit.cover,
                    cacheWidth: _thumbDecodeWidth,
                    gaplessPlayback: true),
                if (session.mask != null)
                  MaskOverlay(
                      mask: session.mask!,
                      colour: p.clay,
                      fit: BoxFit.cover,
                      decodeWidth: _thumbDecodeWidth),
              ],
            )
          : Center(
              child: Icon(Icons.add_rounded, size: 20, color: p.inkFaint),
            ),
    );
  }

  /// The large display: whatever the user is actually looking at right now.
  ///
  /// Built as an [IndexedStack] rather than a swap so the source image stays
  /// **mounted and decoded** while a result is on screen. Rebuilding it on
  /// every switch meant re-reading and re-decoding the file each time, which
  /// is where the stutter when flipping between input and output came from.
  /// Offscreen children keep their state; they just aren't painted.
  Widget _mainDisplay(
    BuildContext context,
    SessionState session,
    RunState run,
    GeneratedImage? focused,
  ) {
    final p = DeskTheme.of(context);
    // A preview frame only means anything while the run is still going.
    // `RunProgress.copyWith` carries `preview` forward (`preview ?? this
    // .preview`), so the last frame survives into the completed state - and
    // because the preview branch is checked first, that pinned the stage to
    // a stale frame forever and made selecting a result do nothing at all.
    final preview = run.isActive ? run.progress.preview : null;
    final source = session.sourceImage;

    // The final link in the preview chain: bytes made it all the way to the
    // widget that paints them. If the server probe says previews are being
    // sent and this never appears, the loss is between RunStore and here.
    if (preview != null) {
      trace('preview', 'RENDERING ${preview.length}B on the stage');
    }

    // Watching the run is a selection like any other, not a mode. It used
    // to win outright, which meant that for the whole of a generation the
    // shelf was decorative: you could not look at the picture you made a
    // minute ago without waiting. Now the run's card holds the stage until
    // you tap something else, and tapping it again comes back.
    final watchingRun = run.isActive && _viewingId == _kRunId;
    // Comparing wins over everything: the point is to see the input
    // *instead of* whatever is on the stage.
    final comparing = _comparing && source != null;
    final (int index, String caption) = comparing
        ? (2, 'INPUT')
        : watchingRun
            ? (0, 'GENERATING')
            : focused != null
                ? (1, 'RESULT')
                : (_viewingInput && source != null)
                    ? (2, 'INPUT')
                    : (3, 'STAGE');

    return MountedSheet(
      caption: caption,
      showHandles: caption == 'INPUT',
      // One InteractiveViewer *outside* the stack, so zoom and pan belong to
      // the stage rather than to a particular picture. Holding compare then
      // shows the input at exactly the same magnification and offset, which
      // is the only way a close comparison is meaningful.
      image: InteractiveViewer(
        transformationController: _view,
        minScale: 1,
        maxScale: 8,
        clipBehavior: Clip.hardEdge,
        child: IndexedStack(
        index: index,
        sizing: StackFit.expand,
        children: [
          preview != null
              ? Image.memory(preview, fit: BoxFit.contain, gaplessPlayback: true)
              // Watching a run that has not sent a frame yet is a real
              // state, and saying so beats a blank sheet - not every server
              // is configured to send previews at all.
              : Center(
                  child: Text('WAITING FOR THE FIRST FRAME',
                      style: Type.micro.copyWith(color: p.inkFaint)),
                ),
          focused != null
              ? _preview(focused,
                  fit: BoxFit.contain, decodeWidth: _stageDecodeWidth(context))
              : const SizedBox.shrink(),
          // Keyed on path so switching source images still swaps the decode,
          // while merely switching *views* does not.
          source != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(source,
                        key: ValueKey(source.path),
                        fit: BoxFit.contain,
                        cacheWidth: _stageDecodeWidth(context),
                        gaplessPlayback: true),
                    // Not while comparing: the whole point of holding
                    // compare is to see the input as it is, and a clay wash
                    // over the very area being changed hides the difference
                    // you are looking for.
                    if (session.mask != null && !comparing)
                      MaskOverlay(
                          mask: session.mask!,
                          colour: p.clay,
                          decodeWidth: _stageDecodeWidth(context)),
                  ],
                )
              : const SizedBox.shrink(),
          Center(
            child: Text('OUTPUTS WILL APPEAR HERE',
                style: Type.micro.copyWith(color: p.inkFaint)),
          ),
        ],
        ),
      ),
    );
  }

  // ===== What the current run actually supports ===== //
  //
  // ComfyUI states this outright: the active workflow declares whether it is
  // txt2img, img2img or inpainting. Forge has no such declaration, so it
  // falls back to its capability flags and infers the rest from the session.

  ComfyWorkflowType? get _workflowType {
    final engineState = _rt.engine.state;
    if (engineState.active != EngineKind.comfy) return null;
    return _rt.engines
        .workflowsFor(engineState.endpoint)
        .activeRecord
        ?.workflowType;
  }

  /// Inpainting only.
  bool get _supportsMask {
    final type = _workflowType;
    if (type == null) return true; // Forge: masking is always available
    return type == ComfyWorkflowType.inpainting;
  }

  /// Anything that takes an input image - img2img and inpainting both.
  bool get _supportsImageInput {
    final type = _workflowType;
    if (type == null) return true;
    return type.needsInputImage;
  }

  // ===== Helpers ===== //

  List<DeskTool> _trayTools(EngineCapabilities capabilities, GenerationMode mode) {
    final tools = <DeskTool>[
      DeskTool(icon: Icons.tune_rounded, name: 'Settings', onTap: _openSettingsDrawer),
    ];
    // Masking and extending need a picture to work on, and they need the
    // run to be one that would actually *use* them. A mask tool on a
    // txt2img workflow paints something the graph then ignores, which is
    // worse than not offering it.
    if (_rt.session.state.hasSourceImage) {
      if (capabilities.masks && _supportsMask) {
        tools.add(DeskTool(
          icon: Icons.brush_rounded,
          name: 'Mask',
          onTap: _openMaskEditor,
        ));
      }
      if (_supportsImageInput) {
        tools.add(DeskTool(
          icon: Icons.open_in_full_rounded,
          name: 'Extend',
          onTap: _openOutpaintEditor,
        ));
      }
    }
    return tools;
  }

  /// The tray while the source image is the main display. Settings leads,
  /// because the generation controls must be reachable from every view -
  /// they were previously unreachable whenever an input image was selected.
  List<DeskTool> _inputTools() => [
        DeskTool(
          icon: Icons.close_rounded,
          name: 'Close',
          onTap: () => setState(() => _viewingId = null),
        ),
        DeskTool(icon: Icons.tune_rounded, name: 'Settings', onTap: _openSettingsDrawer),
        if (_rt.engine.state.capabilities.masks && _supportsMask)
          DeskTool(icon: Icons.brush_rounded, name: 'Mask', onTap: _openMaskEditor),
        if (_supportsImageInput)
          DeskTool(
            icon: Icons.open_in_full_rounded,
            name: 'Extend',
            onTap: _openOutpaintEditor,
          ),
        if (_rt.session.state.mask != null)
          DeskTool(
            icon: Icons.layers_clear_rounded,
            name: 'Clear mask',
            onTap: () {
              _rt.session.setMask(null);
              _notify('Mask cleared.');
            },
          ),
        DeskTool(
          icon: Icons.crop_rounded,
          name: 'Crop',
          onTap: () => _openCropEditor(_rt.library.state),
        ),
        DeskTool(
          icon: Icons.photo_size_select_large_rounded,
          name: 'Resize',
          onTap: () => _openResizeDrawer(_rt.library.state),
        ),
        DeskTool(
          icon: Icons.info_outline_rounded,
          name: 'Details',
          onTap: () => _openMetadataDrawer(_rt.library.state),
        ),
        DeskTool(
          icon: Icons.swap_horiz_rounded,
          name: 'Replace',
          onTap: _pickSourceImage,
        ),
        DeskTool(
          icon: Icons.delete_outline_rounded,
          name: 'Clear',
          onTap: () {
            _rt.session.clearCanvas();
            setState(() => _viewingId = null);
          },
        ),
      ];

  /// The tray while a finished result is the main display: what you can do
  /// to that specific print. Save/Upscale/Delete are real; Edit/Crop are
  /// listed because they belong here but aren't built - tapping says so.
  List<DeskTool> _resultTools(EngineCapabilities capabilities, LibraryState library) {
    return [
      DeskTool(
        icon: Icons.close_rounded,
        name: 'Close',
        onTap: () => setState(() => _viewingId = null),
      ),
      DeskTool(icon: Icons.download_rounded, name: 'Save', onTap: () => _saveFocused(library)),
      // Sending a result to the input is meaningless for a txt2img run -
      // the graph has nowhere to put it.
      if (_supportsImageInput)
        DeskTool(
          icon: Icons.auto_fix_high_rounded,
          name: 'Edit',
          onTap: () => _sendResultToInput(library),
        ),
      DeskTool(
        icon: Icons.crop_rounded,
        name: 'Crop',
        onTap: () => _openCropEditor(library),
      ),
      DeskTool(
        icon: Icons.photo_size_select_large_rounded,
        name: 'Resize',
        onTap: () => _openResizeDrawer(library),
      ),
      DeskTool(
        icon: Icons.info_outline_rounded,
        name: 'Details',
        onTap: () => _openMetadataDrawer(library),
      ),

      DeskTool(
        icon: Icons.delete_outline_rounded,
        name: 'Delete',
        onTap: () => _confirmDeleteFocused(library),
      ),
    ];
  }

  /// Placeholder prints for the run in flight, ahead of the real results -
  /// each shows a shimmer sweep until its frame arrives, so the shelf never
  /// looks inert while something is actually queued.
  List<PrintEntry> _shelfEntries(RunState run, LibraryState library) {
    final entries = <PrintEntry>[];
    if (run.isActive) {
      final batch = run.spec?.sampling.batchSize ?? 1;
      final preview = run.progress.preview;
      final started = run.startedAt?.microsecondsSinceEpoch ?? 0;
      for (var i = 0; i < batch; i++) {
        entries.add(PrintEntry(
          // The first slot is the one that carries the live preview, so it
          // is the one the stage can be pointed back at.
          id: i == 0 ? _kRunId : 'pending-$started-$i',
          image: (i == 0 && preview != null)
              ? Image.memory(preview, fit: BoxFit.cover, gaplessPlayback: true)
              : const _ShimmerPlaceholder(),
        ));
      }
    }
    entries.addAll([
      for (final image in library.images)
        PrintEntry(id: image.id, image: _preview(image, decodeWidth: _thumbDecodeWidth)),
    ]);
    return entries;
  }

  String _selectorLabel(
    EngineState engineState,
    CatalogState catalog,
    ComfyWorkflowService? workflows,
  ) {
    if (engineState.active == EngineKind.forge) {
      return catalog.activeCheckpoint.isEmpty
          ? 'No checkpoint — tap to connect'
          : catalog.activeCheckpoint;
    }
    return workflows?.activeRecord?.name ?? 'No workflow — tap to add one';
  }

  /// `GENERATING · 5/8` - the step counts already ride on every frame, and a
  /// bare phase label threw them away. Between nodes there are no counts, so
  /// it falls back to the phase alone rather than showing a stale pair.
  String _progressCaption(RunProgress progress) {
    final label = (progress.stage ?? progress.phase.label).toUpperCase();
    final current = progress.stepCurrent;
    final total = progress.stepTotal;
    if (current == null || total == null || total <= 0) return label;
    return '$label · $current/$total';
  }

  Color _statusColor(ConnectionStatus status) => switch (status) {
        ConnectionStatus.connected => DeskPalette.good,
        ConnectionStatus.unreachable => DeskPalette.alert,
        ConnectionStatus.connecting || ConnectionStatus.unknown => DeskPalette.caution,
      };

  String _statusText(EngineState engineState, RunState run) {
    if (run.isActive) {
      return (run.progress.stage ?? run.progress.phase.label).toUpperCase();
    }
    if (_connecting) return 'Connecting…';
    if (!engineState.isConnected) {
      return engineState.lastError ?? engineState.status.label;
    }
    if (run.progress.phase == RunPhase.failed) {
      return run.error?.message ?? 'Generation failed';
    }
    return 'Connected to ${engineState.endpoint.display}';
  }

  /// Decode budget for a shelf card, in device pixels - the card is 74pt,
  /// so this is generous even on a 3x screen.
  static const int _thumbDecodeWidth = 260;

  /// Decode budget for the main display: the screen's own pixel width, which
  /// is the most that can actually be shown.
  int _stageDecodeWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixels = (width * dpr).round();
    return pixels < 320 ? 320 : pixels;
  }

  /// Forge hands back data URLs, ComfyUI hands back `/view` URLs; both end up
  /// on the same shelf, so both have to render here.
  ///
  /// [decodeWidth] caps the decode. A phone photo is often 4000px wide; a
  /// shelf card is 74pt. Decoding at full size for every card is what made
  /// flipping between images stutter - the cost is in rasterising pixels
  /// that are then thrown away, and it is paid again on every switch.
  Widget _preview(
    GeneratedImage image, {
    BoxFit fit = BoxFit.cover,
    int? decodeWidth,
  }) =>
      image.isDataUrl
          ? Image.memory(
              base64Decode(image.url.substring(image.url.indexOf(',') + 1)),
              fit: fit,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
            )
          : Image.network(
              image.url,
              fit: fit,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
            );
}

/// A flat, hard-edged "something is happening" sweep for an empty print -
/// diagonal ink stripes translating across, in the same language as the
/// desk's own grain painter. No blur, no gradient, just a moving flat fill,
/// so it costs nothing and never fights DESIGN.md's constraints.
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    if (reduceMotion(context)) return const SizedBox.expand();
    // ClipRect is load-bearing: the painter draws diagonals longer than the
    // box on purpose (so the slant has no seam), and without a clip they
    // spilled out over the neighbouring prints and the whole shelf row.
    return ClipRect(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ShimmerPainter(phase: _c.value, stripe: p.ink.withValues(alpha: 0.07)),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double phase;
  final Color stripe;

  const _ShimmerPainter({required this.phase, required this.stripe});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = 7;
    const spacing = 16.0;
    final travel = phase * spacing * 2;
    for (var x = -size.height - travel; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.phase != phase;
}

/// The Server drawer's contents: an engine switcher plus that engine's
/// address. Local state only - nothing is written back to [EngineStore]
/// until Connect is pressed.
class _EngineDrawerContent extends StatefulWidget {
  final EngineState engineState;
  final void Function(EngineKind kind, EngineEndpoint endpoint) onConnect;

  const _EngineDrawerContent({required this.engineState, required this.onConnect});

  @override
  State<_EngineDrawerContent> createState() => _EngineDrawerContentState();
}

class _EngineDrawerContentState extends State<_EngineDrawerContent> {
  late EngineKind _kind;
  late final TextEditingController _host;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    _kind = widget.engineState.active;
    final endpoint = widget.engineState.endpoints[_kind]!;
    _host = TextEditingController(text: endpoint.host);
    _port = TextEditingController(text: endpoint.port);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _switchKind(EngineKind kind) {
    final endpoint = widget.engineState.endpoints[kind]!;
    setState(() {
      _kind = kind;
      _host.text = endpoint.host;
      _port.text = endpoint.port;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeskDropdown<EngineKind>(
          label: 'Engine',
          value: _kind,
          options: [
            for (final kind in EngineKind.values) DeskOption(value: kind, label: kind.label),
          ],
          onChanged: _switchKind,
        ),
        const SizedBox(height: Space.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: DeskField(label: 'Host', controller: _host)),
            const SizedBox(width: Space.md),
            Expanded(
              child: DeskField(
                label: 'Port',
                controller: _port,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        DeskButton(
          label: 'Connect',
          icon: Icons.link_rounded,
          kind: DeskButtonKind.primary,
          expand: true,
          onPressed: () {
            final endpoint = EngineEndpoint(
              kind: _kind,
              host: _host.text.trim(),
              port: _port.text.trim(),
            );
            Navigator.of(context).pop();
            widget.onConnect(_kind, endpoint);
          },
        ),
      ],
    );
  }
}

/// The Workflows drawer's contents: every workflow saved for this ComfyUI
/// server, tap to select. Importing lives behind the drawer's "Add" action.
class _WorkflowsDrawerContent extends StatelessWidget {
  final ComfyWorkflowService workflows;
  final ValueChanged<ComfyWorkflowRecord> onSelect;
  final ValueChanged<ComfyWorkflowRecord> onManage;

  const _WorkflowsDrawerContent({
    required this.workflows,
    required this.onSelect,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ComfyWorkflowRecord>>(
      valueListenable: workflows.workflows,
      builder: (context, records, _) => ValueListenableBuilder<String?>(
        valueListenable: workflows.activeWorkflowId,
        builder: (context, activeId, _) {
          if (records.isEmpty) {
            final p = DeskTheme.of(context);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxl),
              child: Center(
                child: Text(
                  'No workflows saved for this server yet.\nTap Add to import one.',
                  textAlign: TextAlign.center,
                  style: Type.body.copyWith(color: p.inkFaint),
                ),
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final record in records)
                _WorkflowRow(
                  record: record,
                  selected: record.id == activeId,
                  onTap: () => onSelect(record),
                  onManage: () => onManage(record),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  final Checkpoint checkpoint;
  final bool selected;
  final VoidCallback onTap;

  const _CheckpointRow({
    required this.checkpoint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.ink.withValues(alpha: 0.2), width: Stroke.hairline),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: double.infinity,
              color: selected ? p.clay : Colors.transparent,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                checkpoint.name,
                style: Type.label.copyWith(
                  color: p.ink,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (checkpoint.modules.isNotEmpty) ...[
              Text('+${checkpoint.modules.length} MOD',
                  style: Type.micro.copyWith(color: p.inkFaint)),
              const SizedBox(width: Space.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowRow extends StatelessWidget {
  final ComfyWorkflowRecord record;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onManage;

  const _WorkflowRow({
    required this.record,
    required this.selected,
    required this.onTap,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.ink.withValues(alpha: 0.2), width: Stroke.hairline),
          ),
        ),
        child: Row(
          children: [
            Container(width: 3, height: double.infinity, color: selected ? p.clay : Colors.transparent),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    record.name,
                    style: Type.label.copyWith(
                      color: p.ink,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.workflowType.displayName.toUpperCase(),
                    style: Type.micro.copyWith(color: p.inkFaint),
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onManage,
              child: SizedBox(
                width: Space.touch,
                height: Space.touch,
                child: Icon(Icons.more_vert_rounded, size: 18, color: p.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportChoice {
  final String name;
  final ComfyWorkflowType type;
  const _ImportChoice(this.name, this.type);
}

/// A full-screen step (not a drawer - it follows a native file picker, and
/// stacking a drawer on top of that transition reads oddly) asking what a
/// freshly-picked workflow file should be called and treated as.
class _ImportWorkflowSheet extends StatefulWidget {
  final String defaultName;
  const _ImportWorkflowSheet({required this.defaultName});

  @override
  State<_ImportWorkflowSheet> createState() => _ImportWorkflowSheetState();
}

class _ImportWorkflowSheetState extends State<_ImportWorkflowSheet> {
  late final TextEditingController _name;
  ComfyWorkflowType _type = ComfyWorkflowType.textToImage;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Desk(
      mode: brightness == Brightness.dark ? DeskMode.night : DeskMode.day,
      child: Builder(
        builder: (context) {
          final p = DeskTheme.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              top: false,
              child: Column(children: [
                DeskPageHeader(
                  title: 'Import workflow',
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Padding(
                padding: const EdgeInsets.all(Space.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: Space.xl),
                    DeskField(label: 'Name', controller: _name),
                    const SizedBox(height: Space.lg),
                    DeskDropdown<ComfyWorkflowType>(
                      label: 'Type',
                      value: _type,
                      options: [
                        for (final t in ComfyWorkflowType.values)
                          DeskOption(value: t, label: t.displayName),
                      ],
                      onChanged: (t) => setState(() => _type = t),
                    ),
                    const SizedBox(height: Space.lg),
                    Text(_type.description, style: Type.body.copyWith(color: p.inkFaint)),
                    const Spacer(),
                    DeskButton(
                      label: 'Import',
                      icon: Icons.download_rounded,
                      kind: DeskButtonKind.primary,
                      expand: true,
                      onPressed: () {
                        final name = _name.text.trim();
                        Navigator.of(context).pop(
                          _ImportChoice(name.isEmpty ? widget.defaultName : name, _type),
                        );
                      },
                    ),
                  ],
                ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}


/// Shows a black/white mask over the picture it belongs to, in clay.
///
/// The colour matrix maps luminance onto alpha and forces the RGB to clay,
/// so white (regenerate) paints solid clay and black (keep) is fully
/// transparent - no decoding step and no second image in memory. Without a
/// visible overlay the mask is invisible state: the run behaves completely
/// differently and nothing on screen says why.
class MaskOverlay extends StatelessWidget {
  final Uint8List mask;
  final BoxFit fit;
  final Color colour;

  /// Decode cap. The overlay already costs a `saveLayer` for the opacity and
  /// colour matrix; doing that over a full-resolution mask as well is pure
  /// waste, since the result is only ever shown at widget size.
  final int? decodeWidth;

  const MaskOverlay({
    super.key,
    required this.mask,
    required this.colour,
    this.fit = BoxFit.contain,
    this.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.45,
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(<double>[
            0, 0, 0, 0, (colour.r * 255).toDouble(),
            0, 0, 0, 0, (colour.g * 255).toDouble(),
            0, 0, 0, 0, (colour.b * 255).toDouble(),
            0.3333, 0.3333, 0.3333, 0, 0,
          ]),
          child: Image.memory(mask,
              fit: fit, cacheWidth: decodeWidth, gaplessPlayback: true),
        ),
      ),
    );
  }
}


/// Hold to see the input, release to go back.
///
/// A `Listener` rather than a gesture recogniser: the swap must happen the
/// moment the finger lands. Waiting to find out whether the press is a tap,
/// a drag or a long-press adds exactly the delay that makes a quick A/B
/// comparison useless.
class _CompareButton extends StatefulWidget {
  final ValueChanged<bool> onHoldChanged;

  const _CompareButton({required this.onHoldChanged});

  @override
  State<_CompareButton> createState() => _CompareButtonState();
}

class _CompareButtonState extends State<_CompareButton> {
  bool _held = false;

  void _set(bool held) {
    if (_held == held) return;
    setState(() => _held = held);
    widget.onHoldChanged(held);
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        height: Space.touch,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: _held ? p.clay : p.paper,
          borderRadius: BorderRadius.circular(Corner.control),
          border: Border.all(color: p.ink, width: Stroke.standard),
          boxShadow: (_held ? Elevation.pressed : Elevation.raised).shadows(p.ink),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_rounded,
                size: 16, color: _held ? p.paper : p.ink),
            const SizedBox(width: Space.sm),
            Text(_held ? 'INPUT' : 'HOLD',
                style: Type.micro.copyWith(color: _held ? p.paper : p.inkMuted)),
          ],
        ),
      ),
    );
  }
}


/// A small text-adjacent action. Deliberately lighter than a `DeskButton`:
/// these sit under the prompt in a row of three, and full-height buttons
/// there would compete with Generate for attention.
class _PromptAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool busy;

  const _PromptAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.onLongPress,
    this.busy = false,
  });

  @override
  State<_PromptAction> createState() => _PromptActionState();
}

class _PromptActionState extends State<_PromptAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(_PromptAction old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.busy && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  IconData get icon => widget.icon;
  String get label => widget.label;
  VoidCallback? get onTap => widget.onTap;

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final enabled = onTap != null;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: widget.onLongPress,
        // The Stack wraps the button rather than sitting inside it. Inside,
        // the Container's `alignment` shrink-wrapped its child to the Row's
        // intrinsic size, so `Positioned.fill` filled the *label*, and the
        // border animated around the text instead of around the button.
        // Stack sizes to its first child, so filling now means the button.
        child: Stack(
          children: [
            Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled || widget.busy ? p.paper : p.paperEdge,
                borderRadius: BorderRadius.circular(Corner.control),
                border: Border.all(
                  // While busy the static border steps back, so the
                  // travelling segment reads as motion rather than as a
                  // second outline sitting on top of a solid one.
                  color: widget.busy
                      ? p.ink.withValues(alpha: 0.25)
                      : (enabled ? p.ink : p.inkFaint),
                  width: Stroke.standard,
                ),
                boxShadow: enabled ? Elevation.rest.shadows(p.ink) : const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 14,
                      color: enabled || widget.busy ? p.ink : p.inkFaint),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: Type.label.copyWith(
                          color: enabled || widget.busy ? p.ink : p.inkFaint,
                          fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.busy)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => CustomPaint(
                      painter: _TravellingBorderPainter(
                        progress: _spin.value,
                        colour: p.clay,
                        radius: Corner.control,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A clay segment travelling around the button's own border.
///
/// Chosen over a spinner because the button is short and wide: a spinner
/// would either shrink the label or sit oddly beside it, whereas the border
/// is already there and doing nothing. Uses `PathMetric.extractPath` so the
/// segment follows the rounded corners exactly rather than approximating.
class _TravellingBorderPainter extends CustomPainter {
  final double progress;
  final Color colour;
  final double radius;

  const _TravellingBorderPainter({
    required this.progress,
    required this.colour,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        rect.deflate(Stroke.standard / 2),
        Radius.circular(radius),
      ));

    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = Stroke.live
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      final total = metric.length;
      final segment = total * 0.28;
      final start = (progress * total) % total;
      final end = start + segment;

      if (end <= total) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      } else {
        // Wrapped past the start: draw it as two pieces so the segment
        // travels continuously instead of vanishing at the seam.
        canvas.drawPath(metric.extractPath(start, total), paint);
        canvas.drawPath(metric.extractPath(0, end - total), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TravellingBorderPainter old) =>
      old.progress != progress || old.colour != colour;
}


/// Which prompt action is running. Named rather than boolean, because the
/// buttons need to know *which* one to show as busy.
enum _PromptTask { enhance, generate, describe }


/// The expanded prompt editor. Its own page rather than a drawer: a drawer
/// caps at 88% of the screen and the keyboard would then own most of what is
/// left, which is the problem this screen exists to solve.
class _PromptEditorPage extends StatefulWidget {
  final String initial;

  const _PromptEditorPage({required this.initial});

  @override
  State<_PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends State<_PromptEditorPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Desk(
      mode: brightness == Brightness.dark ? DeskMode.night : DeskMode.day,
      child: Builder(
        builder: (context) {
          final p = DeskTheme.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  DeskPageHeader(
                    title: 'Prompt',
                    onClose: () => Navigator.of(context).pop(),
                    action: DeskButton(
                      label: 'Done',
                      icon: Icons.check_rounded,
                      kind: DeskButtonKind.primary,
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.gutter),
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.paper,
                          borderRadius: BorderRadius.circular(Corner.control),
                          border:
                              Border.all(color: p.ink, width: Stroke.standard),
                          boxShadow: Elevation.raised.shadows(p.ink),
                        ),
                        padding: const EdgeInsets.all(Space.lg),
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          cursorColor: p.clay,
                          cursorWidth: 2,
                          style: Type.body.copyWith(color: p.ink, height: 1.6),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Space.gutter, 0, Space.gutter, Space.md),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) => Row(
                        children: [
                          Text('${value.text.trim().length} CHARACTERS',
                              style: Type.micro.copyWith(color: p.inkFaint)),
                          const Spacer(),
                          DeskButton(
                            label: 'Clear',
                            kind: DeskButtonKind.destructive,
                            onPressed: value.text.isEmpty
                                ? null
                                : () => _controller.clear(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
