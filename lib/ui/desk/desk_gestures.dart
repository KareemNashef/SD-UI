// ==================== Desk Gestures ==================== //

import 'package:flutter/gestures.dart';

/// A pan recogniser that claims the gesture arena immediately.
///
/// Painting on a canvas and dragging an outpaint handle both lose to any
/// scrollable ancestor under the default rules: the parent waits to see
/// whether the drag is a scroll, and by the time it gives up the first few
/// points of the stroke are gone - so a short flick registers as nothing at
/// all and a long one starts late. Resolving `accepted` on pointer-down
/// means the canvas owns the drag from the first frame.
///
/// Carried over from the previous build, where this was the fix for masks
/// that silently dropped their opening strokes.
class AlwaysWinPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'alwaysWin';
}
