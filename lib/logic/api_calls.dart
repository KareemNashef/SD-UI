// ==================== API Calls ==================== //

// Flutter imports
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// API Calls Implementation
//
// Generic calls route through the active backend (globalBackend); calls
// that only make sense for one backend route through that backend's
// dedicated accessor (globalForgeBackend / globalComfyBackend) so they
// never silently no-op when the other backend is active.

// Check if the server is online
Future<void> checkServerStatus() async {
  globalServerStatus.value = await globalBackend.checkStatus();
}

// Get checkpoint data from the server (Forge only)
Future<void> syncCheckpointDataFromServer({bool force = false}) async {
  await globalForgeBackend.syncCheckpoints(force: force);
}

// Change the checkpoint (Forge only)
Future<void> setCheckpoint() async {
  await globalForgeBackend.setCheckpoint(globalCurrentCheckpointName);
}

// Get the VAE and text-encoder files available to Forge Neo
Future<List<String>> fetchForgeModules() async {
  return globalForgeBackend.fetchForgeModules();
}

// Apply the active checkpoint's VAE and text-encoder selection
Future<void> applyCheckpointConfiguration() async {
  await globalForgeBackend.applyCheckpointConfiguration(
    globalCurrentCheckpointName,
  );
}

// Load lora data from the server (Forge only)
Future<void> loadLoraDataFromServer() async {
  await globalForgeBackend.loadLoras();
}

// Fetch raw Forge progress data from the server
Future<Map<String, dynamic>> fetchProgress() async {
  return await globalForgeBackend.fetchRawProgress();
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

// Fetch PNG info (Forge only)
Future<Map<String, dynamic>> postPngInfo(String base64Image) async {
  return await globalForgeBackend.getPngInfo(base64Image);
}

// Interrupt generation on the active backend
Future<void> interruptGeneration() async {
  await globalBackend.interruptGeneration();
}
