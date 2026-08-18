// ==================== Runtime Scope ==================== //

import 'package:flutter/widgets.dart';

import 'package:sd_companion/runtime/aperture_runtime.dart';

/// Makes the [ApertureRuntime] available to the widget tree.
///
/// This is how the UI reaches state without importing global variables. A
/// screen calls `RuntimeScope.of(context).session` and gets the real store;
/// a widget test wraps its subject in a scope holding a test runtime and
/// gets full control with no mocking framework.
class RuntimeScope extends InheritedWidget {
  final ApertureRuntime runtime;

  const RuntimeScope({
    super.key,
    required this.runtime,
    required super.child,
  });

  static ApertureRuntime of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RuntimeScope>();
    assert(scope != null, 'No RuntimeScope found above this widget.');
    return scope!.runtime;
  }

  /// Reads the runtime without subscribing. Use in callbacks, where there is
  /// nothing to rebuild.
  static ApertureRuntime read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<RuntimeScope>();
    assert(scope != null, 'No RuntimeScope found above this widget.');
    return scope!.runtime;
  }

  @override
  bool updateShouldNotify(RuntimeScope oldWidget) =>
      !identical(oldWidget.runtime, runtime);
}
