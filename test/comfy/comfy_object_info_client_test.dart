import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/data/engines/comfy/comfy_object_info_client.dart';
import 'package:sd_companion/core/app_error.dart';

const _endpoint =
    EngineEndpoint(kind: EngineKind.comfy, host: '127.0.0.1', port: '8188');

void main() {
  test('parses a successful /object_info/<type> response', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/object_info/KSampler');
      return http.Response(
        jsonEncode({
          'KSampler': {
            'input': {
              'required': {
                'model': ['MODEL'],
                'steps': ['INT', {'default': 20}],
              },
            },
            'input_order': {
              'required': ['model', 'steps'],
            },
            'output': ['LATENT'],
          },
        }),
        200,
      );
    });

    final provider = HttpComfyNodeSchemaProvider(_endpoint, client: client);
    final schema = await provider.schemaFor('KSampler');

    expect(schema.known, isTrue);
    expect(schema.inputs.map((i) => i.name), ['model', 'steps']);
    expect(schema.widgetSlots.map((w) => w.name), ['steps']);
  });

  test('caches results so a repeated lookup does not re-hit the network', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      return http.Response(jsonEncode({'LoadImage': {'input': {'required': {}}}}), 200);
    });

    final provider = HttpComfyNodeSchemaProvider(_endpoint, client: client);
    await provider.schemaFor('LoadImage');
    await provider.schemaFor('LoadImage');

    expect(callCount, 1);
  });

  test('treats a type missing from the response as unknown, not an error', () async {
    final client = MockClient((request) async => http.Response('{}', 200));
    final provider = HttpComfyNodeSchemaProvider(_endpoint, client: client);
    final schema = await provider.schemaFor('Note');
    expect(schema.known, isFalse);
  });

  test('surfaces a typed AppError on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('server error', 500));
    final provider = HttpComfyNodeSchemaProvider(_endpoint, client: client);

    expect(
      () => provider.schemaFor('KSampler'),
      throwsA(isA<ServerError>()),
    );
  });

  test('surfaces a typed AppError when the server is unreachable', () async {
    final client = MockClient((request) async => throw Exception('connection refused'));
    final provider = HttpComfyNodeSchemaProvider(_endpoint, client: client);

    expect(
      () => provider.schemaFor('KSampler'),
      throwsA(isA<UnreachableError>()),
    );
  });
}
