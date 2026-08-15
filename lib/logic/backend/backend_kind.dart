// ==================== Backend Kind ==================== //

enum BackendKind { forge, comfy }

extension BackendKindLabel on BackendKind {
  String get displayName => switch (this) {
    BackendKind.forge => 'Forge Neo',
    BackendKind.comfy => 'ComfyUI',
  };

  String get storageKey => switch (this) {
    BackendKind.forge => 'forge',
    BackendKind.comfy => 'comfy',
  };

  static BackendKind fromStorageKey(String? key) => switch (key) {
    'comfy' => BackendKind.comfy,
    _ => BackendKind.forge,
  };
}
