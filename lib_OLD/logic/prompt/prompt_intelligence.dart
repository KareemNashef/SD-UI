// ==================== Prompt Intelligence ==================== //

// Prompt Intelligence Implementation

class PromptIntelligence {
  // ===== Class Methods ===== //

  static Map<String, PromptElement> analyzeHistory(List<String> prompts) {
    Map<String, PromptElement> elements = {};
    for (String prompt in prompts) {
      List<String> parts = prompt
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      for (String part in parts) {
        String normalized = part.toLowerCase();
        if (elements.containsKey(normalized)) {
          elements[normalized]!.count++;
          elements[normalized]!.lastUsed = DateTime.now();
        } else {
          elements[normalized] = PromptElement(
            text: part,
            count: 1,
            lastUsed: DateTime.now(),
          );
        }
      }
    }
    return elements;
  }

  static List<String> getFrequentElements(
    Map<String, PromptElement> elements, {
    int minCount = 2,
  }) {
    var sorted = elements.values.where((e) => e.count >= minCount).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return sorted.map((e) => e.text).toList();
  }
}

// ===== Prompt Element Class ===== //

class PromptElement {
  String text;
  int count;
  DateTime lastUsed;
  PromptElement({
    required this.text,
    required this.count,
    required this.lastUsed,
  });
}
