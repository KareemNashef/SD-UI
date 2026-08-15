import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/comfy/comfy_object_info_client.dart';
import 'package:sd_companion/logic/models/generation_models.dart';

const _profile = ServerProfile(kind: BackendKind.comfy, host: '127.0.0.1', port: '8188');

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

    final provider = HttpComfyNodeSchemaProvider(_profile, client: client);
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

    final provider = HttpComfyNodeSchemaProvider(_profile, client: client);
    await provider.schemaFor('LoadImage');
    await provider.schemaFor('LoadImage');

    expect(callCount, 1);
  });

  test('treats a type missing from the response as unknown, not an error', () async {
    final client = MockClient((request) async => http.Response('{}', 200));
    final provider = HttpComfyNodeSchemaProvider(_profile, client: client);
    final schema = await provider.schemaFor('Note');
    expect(schema.known, isFalse);
  });

  test('surfaces a typed BackendException on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('server error', 500));
    final provider = HttpComfyNodeSchemaProvider(_profile, client: client);

    expect(
      () => provider.schemaFor('KSampler'),
      throwsA(isA<BackendException>().having((e) => e.kind, 'kind', BackendErrorKind.server)),
    );
  });

  test('surfaces a typed BackendException when the server is unreachable', () async {
    final client = MockClient((request) async => throw Exception('connection refused'));
    final provider = HttpComfyNodeSchemaProvider(_profile, client: client);

    expect(
      () => provider.schemaFor('KSampler'),
      throwsA(isA<BackendException>().having((e) => e.kind, 'kind', BackendErrorKind.connection)),
    );
  });
}
