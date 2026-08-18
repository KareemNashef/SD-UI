// Covers the URL building and identity rules the whole data layer depends
// on. These are cheap to get wrong and expensive to notice: a bad `id` makes
// two different ComfyUI servers share one workflow store, and a bad ws scheme
// silently kills live progress behind TLS.

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/domain/engine/engine_capabilities.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';

void main() {
  group('EngineEndpoint', () {
    test('builds http and ws URIs for local Comfy defaults', () {
      const e = EngineEndpoint(
          kind: EngineKind.comfy, host: '127.0.0.1', port: '8188');
      expect(e.http('/system_stats').toString(),
          'http://127.0.0.1:8188/system_stats');
      expect(e.ws('/ws', {'clientId': 'abc'}).toString(),
          'ws://127.0.0.1:8188/ws?clientId=abc');
    });

    test('derives wss from an https scheme', () {
      const e = EngineEndpoint(
          kind: EngineKind.comfy,
          host: 'my.host',
          port: '443',
          scheme: 'https');
      expect(e.ws('/ws').scheme, 'wss');
      expect(e.http('/prompt').scheme, 'https');
    });

    test('respects an optional base path for reverse proxies', () {
      const e = EngineEndpoint(
        kind: EngineKind.comfy,
        host: 'proxy.local',
        port: '8080',
        basePath: 'comfy',
      );
      expect(e.http('/prompt').toString(), 'http://proxy.local:8080/comfy/prompt');
    });

    test('id is stable and namespaces by kind/host/port', () {
      const forge =
          EngineEndpoint(kind: EngineKind.forge, host: '127.0.0.1', port: '7860');
      const comfy =
          EngineEndpoint(kind: EngineKind.comfy, host: '127.0.0.1', port: '8188');
      expect(forge.id, isNot(comfy.id));
      const forgeAgain =
          EngineEndpoint(kind: EngineKind.forge, host: '127.0.0.1', port: '7860');
      expect(forge.id, forgeAgain.id);
      expect(forge, forgeAgain); // equality rides on id
    });

    test('defaultFor uses each engine\'s own port', () {
      expect(EngineEndpoint.defaultFor(EngineKind.forge).port, '7860');
      expect(EngineEndpoint.defaultFor(EngineKind.comfy).port, '8188');
    });

    test('survives a JSON round trip', () {
      const e = EngineEndpoint(
        kind: EngineKind.comfy,
        host: 'box.lan',
        port: '8188',
        scheme: 'https',
        basePath: 'ui',
      );
      expect(EngineEndpoint.fromJson(e.toJson()), e);
    });
  });

  group('EngineCapabilities', () {
    test('Forge keeps checkpoint/LoRA features that Comfy hides', () {
      expect(EngineCapabilities.of(EngineKind.forge).checkpoints, isTrue);
      expect(EngineCapabilities.of(EngineKind.comfy).checkpoints, isFalse);
      expect(EngineCapabilities.of(EngineKind.forge).loras, isTrue);
      expect(EngineCapabilities.of(EngineKind.comfy).loras, isFalse);
    });

    test('Comfy exposes workflows and live preview that Forge does not', () {
      expect(EngineCapabilities.of(EngineKind.comfy).workflows, isTrue);
      expect(EngineCapabilities.of(EngineKind.forge).workflows, isFalse);
      expect(EngineCapabilities.of(EngineKind.comfy).livePreview, isTrue);
      expect(EngineCapabilities.of(EngineKind.forge).livePreview, isFalse);
    });

    test('both engines support interrupt', () {
      expect(EngineCapabilities.forge.interrupt, isTrue);
      expect(EngineCapabilities.comfy.interrupt, isTrue);
    });
  });
}
