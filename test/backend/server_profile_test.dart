import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/logic/backend/backend_capabilities.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';

void main() {
  group('ServerProfile', () {
    test('builds http and ws URIs for local Comfy defaults', () {
      const profile = ServerProfile(kind: BackendKind.comfy, host: '127.0.0.1', port: '8188');
      expect(profile.httpUri('/system_stats').toString(), 'http://127.0.0.1:8188/system_stats');
      expect(profile.wsUri('/ws', {'clientId': 'abc'}).toString(), 'ws://127.0.0.1:8188/ws?clientId=abc');
    });

    test('derives wss from https scheme', () {
      const profile = ServerProfile(kind: BackendKind.comfy, host: 'my.host', port: '443', scheme: 'https');
      expect(profile.wsUri('/ws').scheme, 'wss');
      expect(profile.httpUri('/prompt').scheme, 'https');
    });

    test('respects an optional base path for reverse proxies', () {
      const profile = ServerProfile(
        kind: BackendKind.comfy,
        host: 'proxy.local',
        port: '8080',
        basePath: 'comfy',
      );
      expect(profile.httpUri('/prompt').toString(), 'http://proxy.local:8080/comfy/prompt');
    });

    test('id is stable and namespaces by kind/host/port', () {
      const forge = ServerProfile(kind: BackendKind.forge, host: '127.0.0.1', port: '7860');
      const comfy = ServerProfile(kind: BackendKind.comfy, host: '127.0.0.1', port: '8188');
      expect(forge.id, isNot(comfy.id));
      const forgeAgain = ServerProfile(kind: BackendKind.forge, host: '127.0.0.1', port: '7860');
      expect(forge.id, forgeAgain.id);
    });
  });

  group('BackendCapabilities', () {
    test('Forge keeps checkpoint/LoRA/testing features that Comfy hides', () {
      expect(BackendCapabilities.forKind(BackendKind.forge).checkpoints, isTrue);
      expect(BackendCapabilities.forKind(BackendKind.comfy).checkpoints, isFalse);
      expect(BackendCapabilities.forKind(BackendKind.forge).loras, isTrue);
      expect(BackendCapabilities.forKind(BackendKind.comfy).loras, isFalse);
    });

    test('Comfy exposes workflows and live preview that Forge does not', () {
      expect(BackendCapabilities.forKind(BackendKind.comfy).workflows, isTrue);
      expect(BackendCapabilities.forKind(BackendKind.forge).workflows, isFalse);
      expect(BackendCapabilities.forKind(BackendKind.comfy).livePreview, isTrue);
      expect(BackendCapabilities.forKind(BackendKind.forge).livePreview, isFalse);
    });

    test('both backends support interrupt', () {
      expect(BackendCapabilities.forge.interrupt, isTrue);
      expect(BackendCapabilities.comfy.interrupt, isTrue);
    });
  });
}
