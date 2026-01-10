// ==================== Image Metadata Parser ==================== //

/// Parses image info string from PNG metadata into a structured map
Map<String, String> parseImageInfo(String info) {
  final map = <String, String>{};
  final lines = info.split('\n');

  final promptBuffer = <String>[];
  final negativeBuffer = <String>[];

  bool inNegative = false;
  bool inMeta = false;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    // Detect start of metadata reliably
    if (line.startsWith('Steps:')) {
      inMeta = true;
    }

    if (line.startsWith('Negative prompt:')) {
      inNegative = true;
      inMeta = false;
      negativeBuffer.add(line.substring('Negative prompt:'.length).trim());
      continue;
    }

    if (inMeta) {
      // Split on commas not inside quotes
      final parts = line.split(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)'));
      for (final part in parts) {
        final idx = part.indexOf(':');
        if (idx == -1) continue;
        final key = part.substring(0, idx).trim();
        final value = part.substring(idx + 1).trim();
        map[key] = value;
      }
      continue;
    }

    if (inNegative) {
      negativeBuffer.add(line);
    } else {
      promptBuffer.add(line);
    }
  }

  if (promptBuffer.isNotEmpty) {
    map['prompt'] = promptBuffer.join(' ');
  }
  if (negativeBuffer.isNotEmpty) {
    map['negativePrompt'] = negativeBuffer.join(' ');
  }

  return map;
}
