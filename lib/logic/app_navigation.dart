// ==================== App Navigation ==================== //
//
// A UI-agnostic navigation intent bus.
//
// The logic layer sometimes needs to *request* that the app move somewhere
// (e.g. checkpoint testing wants the results view brought forward when a
// batch starts). Previously that was done by reaching directly into the
// widget tree through a GlobalKey<MainPageState>, which meant the logic
// layer imported a concrete page and could only ever work with that exact
// shell.
//
// Instead, logic publishes an intent here and whatever UI shell happens to
// be mounted subscribes and decides how to honor it - a tab switch, a push,
// a sheet, or nothing at all. Logic never learns what the UI looks like.

import 'dart:async';

/// The app's top-level destinations, named by what the user is doing rather
/// than by any particular widget or tab index.
enum AppDestination {
  /// Composing and running a generation.
  create,

  /// Browsing generated results.
  gallery,

  /// Server, engine and workflow configuration.
  settings,
}

class AppNavigation {
  AppNavigation._();

  static final StreamController<AppDestination> _controller =
      StreamController<AppDestination>.broadcast();

  /// Navigation intents published by the logic layer. The UI shell listens
  /// to this and performs the actual navigation.
  static Stream<AppDestination> get requests => _controller.stream;

  /// Requests that the app move to [destination]. Safe to call when no UI
  /// is listening - the intent is simply dropped.
  static void go(AppDestination destination) => _controller.add(destination);

  /// Convenience aliases matching how the logic layer reads.
  static void goToCreate() => go(AppDestination.create);
  static void goToGallery() => go(AppDestination.gallery);
  static void goToSettings() => go(AppDestination.settings);
}
