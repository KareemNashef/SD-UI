// ==================== Engine Kind ==================== //
//
// "Engine" rather than "backend": these are two different image-generation
// engines the app drives, and the app is a remote control for exactly one
// of them at a time. "Backend" suggested a server tier; this is the thing
// that actually makes the picture.

enum EngineKind {
  forge,
  comfy;

  /// Human-facing name. The only string that should ever reach the UI.
  String get label => switch (this) {
        EngineKind.forge => 'Forge Neo',
        EngineKind.comfy => 'ComfyUI',
      };

  /// Stable key for persistence. Must never change once shipped - existing
  /// installs have these written to disk.
  String get storageKey => switch (this) {
        EngineKind.forge => 'forge',
        EngineKind.comfy => 'comfy',
      };

  /// Default port each engine listens on out of the box.
  String get defaultPort => switch (this) {
        EngineKind.forge => '7860',
        EngineKind.comfy => '8188',
      };

  static EngineKind fromStorageKey(String? key) => switch (key) {
        'comfy' => EngineKind.comfy,
        _ => EngineKind.forge,
      };
}
