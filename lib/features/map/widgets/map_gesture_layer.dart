import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Captures tap/long-press gestures across the entire map without blocking pan/zoom.
class MapGestureLayer extends StatefulWidget {
  const MapGestureLayer({
    required this.child,
    this.onLongPress,
    this.onTap,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final ValueChanged<Offset>? onLongPress;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<MapGestureLayer> createState() => _MapGestureLayerState();
}

class _MapGestureLayerState extends State<MapGestureLayer> {
  static const Duration _longPressDuration = Duration(milliseconds: 500);
  static const double _moveThreshold = 12.0;

  Timer? _timer;
  Offset? _downPosition;
  bool _longPressTriggered = false;
  bool _movementExceeded = false;
  int _pointerCount = 0;
  int? _primaryPointer;

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) {
      return;
    }
    _pointerCount += 1;
    if (_pointerCount == 1) {
      _primaryPointer = event.pointer;
      _movementExceeded = false;
      _startTimer(event.localPosition);
    } else {
      _movementExceeded = true;
      _cancelTimer();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.enabled ||
        _primaryPointer == null ||
        event.pointer != _primaryPointer ||
        _longPressTriggered) {
      return;
    }
    final down = _downPosition;
    if (down == null) {
      return;
    }
    final dx = event.localPosition.dx - down.dx;
    final dy = event.localPosition.dy - down.dy;
    final distanceSquared = dx * dx + dy * dy;
    if (distanceSquared >= _moveThreshold * _moveThreshold) {
      _movementExceeded = true;
      _cancelTimer();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!widget.enabled) {
      _resetPointers();
      return;
    }
    _pointerCount = math.max(0, _pointerCount - 1);
    if (event.pointer == _primaryPointer) {
      final didTriggerLongPress = _longPressTriggered;
      final shouldTap =
          !didTriggerLongPress && !_movementExceeded && _downPosition != null;
      _resetPrimaryState();
      if (shouldTap) {
        widget.onTap?.call();
      }
    }
    if (_pointerCount == 0) {
      _primaryPointer = null;
      _movementExceeded = false;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _resetPointers();
  }

  void _startTimer(Offset position) {
    _downPosition = position;
    _longPressTriggered = false;
    _timer?.cancel();
    _timer = Timer(_longPressDuration, () {
      final down = _downPosition;
      if (down == null) {
        return;
      }
      _longPressTriggered = true;
      widget.onLongPress?.call(down);
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _resetPrimaryState() {
    _cancelTimer();
    _downPosition = null;
    _longPressTriggered = false;
  }

  void _resetPointers() {
    _pointerCount = 0;
    _primaryPointer = null;
    _movementExceeded = false;
    _resetPrimaryState();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
