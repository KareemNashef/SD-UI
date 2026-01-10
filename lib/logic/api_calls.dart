// ==================== API Calls ==================== //

// Flutter imports
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Check if the server is online
Future<void> checkServerStatus() async {
  globalServerStatus.value = await globalBackend.checkStatus();
}

// Get checkpoint data from the server
Future<void> syncCheckpointDataFromServer({bool force = false}) async {
  await globalBackend.syncCheckpoints(force: force);
}

// Change the checkpoint
Future<void> setCheckpoint() async {
  await globalBackend.setCheckpoint(globalCurrentCheckpointName);
}

// Load lora data from the server
Future<void> loadLoraDataFromServer() async {
  await globalBackend.loadLoras();
}

// Fetch progress data from the server
Future<Map<String, dynamic>> fetchProgress() async {
  return await globalBackend.fetchProgress();
}

// Internal helper to fetch image bytes from a URL
Future<Uint8List> fetchImageBytes(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    return response.bodyBytes;
  } else {
    throw Exception('Failed to load image: ${response.statusCode}');
  }
}

// Fetch PNG info
Future<Map<String, dynamic>> postPngInfo(String base64Image) async {
  return await globalBackend.getPngInfo(base64Image);
}
