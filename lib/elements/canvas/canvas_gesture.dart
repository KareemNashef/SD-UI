// ==================== Canvas Gesture ==================== //

// Flutter imports
import 'package:flutter/gestures.dart';

// Canvas Gesture Implementation

class AlwaysWinPanGestureRecognizer extends PanGestureRecognizer {
  // ===== Class Methods ===== //

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'alwaysWin';
}
