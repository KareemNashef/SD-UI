// Covers each store's behaviour, focusing on the invariants the old loose
// globals could not enforce - the ones that produced real bugs.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';
import 'package:sd_companion/state/catalog_store.dart';
import 'package:sd_companion/state/engine_store.dart';
import 'package:sd_companion/state/library_store.dart';
import 'package:sd_companion/state/prompt_book_store.dart';
import 'package:sd_companion/state/run_store.dart';
import 'package:sd_companion/state/session_store.dart';
import 'package:sd_companion/domain/catalog/checkpoint.dart';

void main() {
  group('EngineStore', () {
    test('capabilities are derived, so they can never disagree with the engine', () {
      final store = EngineStore();
      addTearDown(store.dispose);

      expect(store.active, EngineKind.forge);
      expect(store.capabilities.loras, isTrue);
      expect(store.capabilities.workflows, isFalse);

      store.setActive(EngineKind.comfy);

      expect(store.capabilities.loras, isFalse);
      expect(store.capabilities.workflows, isTrue);
    });

    test('switching engines clears connection status', () {
      final store = EngineStore();
      addTearDown(store.dispose);

      store.markConnected();
      expect(store.state.isConnected, isTrue);

      store.setActive(EngineKind.comfy);

      expect(store.state.isConnected, isFalse,
          reason: 'a status from the previous engine says nothing about this one');
      expect(store.state.status, ConnectionStatus.unknown);
    });

    test('each engine keeps its own address across a switch', () {
      final store = EngineStore();
      addTearDown(store.dispose);

      store.setAddress(host: '10.0.0.5', port: '7860');
      store.setActive(EngineKind.comfy);
      store.setAddress(host: '10.0.0.9', port: '8188');

      expect(store.endpoint.host, '10.0.0.9');

      store.setActive(EngineKind.forge);
      expect(store.endpoint.host, '10.0.0.5',
          reason: 'switching back must not lose the other engine address');
    });

    test('marking unreachable records why', () {
      final store = EngineStore();
      addTearDown(store.dispose);

      store.markUnreachable('refused');
      expect(store.state.status, ConnectionStatus.unreachable);
      expect(store.state.lastError, 'refused');
    });
  });

  group('SessionStore', () {
    test('mode is derived from what is actually supplied', () {
      final store = SessionStore();
      addTearDown(store.dispose);

      expect(store.state.mode, GenerationMode.textToImage);
    });

    test('dropping the source image also drops the mask', () {
      final store = SessionStore();
      addTearDown(store.dispose);

      store.setMask(Uint8List.fromList([1, 2, 3]));
      expect(store.state.mask, isNotNull);

      store.setSourceImage(null);

      expect(store.state.mask, isNull,
          reason: 'a mask without the image it was painted on is meaningless');
    });

    test('tuneSampling applies a partial change without rebuilding the object', () {
      final store = SessionStore();
      addTearDown(store.dispose);

      store.tuneSampling((p) => p.copyWith(steps: 40));

      expect(store.state.sampling.steps, 40);
      expect(store.state.sampling.cfgScale, 7.0, reason: 'other params untouched');
    });

    test('is observable - the failure mode the old plain globals had', () {
      final store = SessionStore();
      addTearDown(store.dispose);

      var notifications = 0;
      store.addListener(() => notifications++);

      store.setPrompt('a cat');
      store.tuneSampling((p) => p.copyWith(steps: 30));

      expect(notifications, 2);
    });
  });

  group('RunStore', () {
    const spec = GenerationSpec(prompt: 'test');

    test('begin moves to queued and records the spec', () {
      final store = RunStore();
      addTearDown(store.dispose);

      store.begin(spec);

      expect(store.state.phase, RunPhase.queued);
      expect(store.state.spec, same(spec));
      expect(store.isActive, isTrue);
    });

    test('drops late progress for a run that already finished', () {
      final store = RunStore();
      addTearDown(store.dispose);

      store.begin(spec);
      store.succeed();
      expect(store.state.phase, RunPhase.completed);

      // A slow WebSocket frame arriving after completion.
      store.report(const RunProgress(phase: RunPhase.running, fraction: 0.5));

      expect(store.state.phase, RunPhase.completed,
          reason: 'a late frame must not resurrect a finished run');
    });

    test('failing records the error and the message', () {
      final store = RunStore();
      addTearDown(store.dispose);

      store.begin(spec);
      store.fail(const ExecutionError('node blew up', nodeId: '7'));

      expect(store.state.phase, RunPhase.failed);
      expect(store.state.error, isA<ExecutionError>());
      expect(store.state.progress.failureMessage, 'node blew up');
    });

    test('succeed pins progress to 100%', () {
      final store = RunStore();
      addTearDown(store.dispose);

      store.begin(spec);
      store.report(const RunProgress(phase: RunPhase.running, fraction: 0.4));
      store.succeed();

      expect(store.state.progress.percent, 100);
    });
  });

  group('LibraryStore', () {
    GeneratedImage img(String id) =>
        GeneratedImage(id: id, url: 'https://x/$id', engine: EngineKind.forge);

    test('adding selects the newest image', () {
      final store = LibraryStore();
      addTearDown(store.dispose);

      store.add([img('a'), img('b')]);

      expect(store.state.count, 2);
      expect(store.state.selectedId, 'a', reason: 'newest first');
    });

    test('newest images go to the front', () {
      final store = LibraryStore();
      addTearDown(store.dispose);

      store.add([img('old')]);
      store.add([img('new')]);

      expect(store.images.first.id, 'new');
    });

    test('removing the selected image moves selection to a neighbour', () {
      final store = LibraryStore();
      addTearDown(store.dispose);

      store.add([img('c')]);
      store.add([img('b')]);
      store.add([img('a')]); // order: a, b, c

      store.select('b');
      store.remove('b');

      expect(store.state.selectedId, 'c',
          reason: 'selection should land on the image that took the slot');
      expect(store.state.count, 2);
    });

    test('removing the last image clears selection rather than dangling', () {
      final store = LibraryStore();
      addTearDown(store.dispose);

      store.add([img('only')]);
      store.remove('only');

      expect(store.state.isEmpty, isTrue);
      expect(store.state.selectedId, isNull);
    });
  });

  group('PromptBookStore', () {
    test('recording moves an existing prompt to the front', () {
      final store = PromptBookStore();
      addTearDown(store.dispose);

      store.record('first');
      store.record('second');
      store.record('first');

      expect(store.state.history, ['first', 'second'],
          reason: 'history is most-recent-first, not insertion-ordered');
    });

    test('ignores blank prompts', () {
      final store = PromptBookStore();
      addTearDown(store.dispose);

      store.record('   ');
      expect(store.state.history, isEmpty);
    });

    test('history is capped so it cannot grow without bound', () {
      final store = PromptBookStore();
      addTearDown(store.dispose);

      for (var i = 0; i < PromptBookStore.maxHistory + 25; i++) {
        store.record('prompt $i');
      }

      expect(store.state.history.length, PromptBookStore.maxHistory);
      expect(store.state.history.first, 'prompt ${PromptBookStore.maxHistory + 24}');
    });

    test('fragments rank by how often each appears', () {
      final store = PromptBookStore();
      addTearDown(store.dispose);

      store.record('golden hour, cinematic');
      store.record('golden hour, portrait');
      store.record('golden hour');

      final top = store.state.fragments.first;
      expect(top.text, 'golden hour');
      expect(top.uses, 3);
    });

    test('fragment counting is case-insensitive, showing the newest casing', () {
      final store = PromptBookStore();
      addTearDown(store.dispose);

      store.record('Golden Hour');
      store.record('golden hour');

      expect(store.state.fragments.length, 1,
          reason: 'differing case must not split one fragment into two');
      expect(store.state.fragments.first.uses, 2);
      expect(store.state.fragments.first.text, 'golden hour',
          reason: 'history is most-recent-first, so the latest casing is shown');
    });

    test('toggling a favourite adds then removes it', () {
      final store = PromptBookStore();
      addTearDown(store.dispose);

      store.toggleFavourite('keep me');
      expect(store.state.isFavourite('keep me'), isTrue);

      store.toggleFavourite('keep me');
      expect(store.state.isFavourite('keep me'), isFalse);
    });

    test('onChanged fires on mutation so the owner can persist', () {
      var saves = 0;
      final store = PromptBookStore(onChanged: () => saves++);
      addTearDown(store.dispose);

      store.record('one');
      store.toggleFavourite('one');

      expect(saves, 2);
    });

    test('hydrate does not trigger a save', () {
      var saves = 0;
      final store = PromptBookStore(onChanged: () => saves++);
      addTearDown(store.dispose);

      store.hydrate(const PromptBookState(history: ['loaded']));

      expect(store.state.history, ['loaded']);
      expect(saves, 0, reason: 'persisting straight back after a load is pointless');
    });
  });

  group('CatalogStore', () {
    test('a vanished active checkpoint falls back instead of dangling', () {
      final store = CatalogStore();
      addTearDown(store.dispose);

      store.setCheckpoints([const Checkpoint(name: 'a'), const Checkpoint(name: 'b')]);
      store.selectCheckpoint('b');

      // Server refreshed and 'b' is gone.
      store.setCheckpoints([const Checkpoint(name: 'a')]);

      expect(store.state.activeCheckpoint, 'a');
      expect(store.state.active, isNotNull);
    });

    test('a surviving active checkpoint is kept across a refresh', () {
      final store = CatalogStore();
      addTearDown(store.dispose);

      store.setCheckpoints([const Checkpoint(name: 'a'), const Checkpoint(name: 'b')]);
      store.selectCheckpoint('b');
      store.setCheckpoints([const Checkpoint(name: 'a'), const Checkpoint(name: 'b')]);

      expect(store.state.activeCheckpoint, 'b');
    });

    test('zero weight removes a LoRA rather than sending a no-op', () {
      final store = CatalogStore();
      addTearDown(store.dispose);

      store.setLoraWeight('detail', 0.8);
      expect(store.state.loraWeights, containsPair('detail', 0.8));

      store.setLoraWeight('detail', 0);
      expect(store.state.loraWeights, isEmpty);
    });

    test('builds the prompt fragment Forge expects, including tags', () {
      final store = CatalogStore();
      addTearDown(store.dispose);

      store.setLoraWeight('detail', 0.85);
      store.setLoraTags('detail', {'sharp', 'crisp'});

      final fragment = store.buildPromptFragment();

      expect(fragment, contains('<lora:detail:0.85>'));
      expect(fragment, contains('sharp'));
      expect(fragment, contains('crisp'));
    });

    test('produces nothing when no LoRA is selected', () {
      final store = CatalogStore();
      addTearDown(store.dispose);
      expect(store.buildPromptFragment(), isEmpty);
    });

    test('groups checkpoints by base model for the picker', () {
      final store = CatalogStore();
      addTearDown(store.dispose);

      store.setCheckpoints([
        const Checkpoint(name: 'x', baseModel: 'SDXL'),
        const Checkpoint(name: 'y', baseModel: 'SDXL'),
        const Checkpoint(name: 'z', baseModel: 'Flux'),
      ]);

      final groups = store.state.byBaseModel;
      expect(groups['SDXL'], hasLength(2));
      expect(groups['Flux'], hasLength(1));
    });
  });
}
