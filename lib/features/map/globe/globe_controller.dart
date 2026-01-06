import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:world_visit_app/features/map/globe/globe_projection.dart';

/// Controller for managing globe rotation and zoom state.
///
/// Handles:
/// - Rotation state (rotationX, rotationY)
/// - Zoom/scale state
/// - Drag gestures to update rotation
/// - Pinch gestures to update scale
class GlobeController extends ChangeNotifier {
  GlobeController({
    double initialRotationX =
        0.3, // Slight tilt to show more of the northern hemisphere
    double initialRotationY = 0.0, // Facing longitude 0 (Atlantic/Europe)
    double initialScale = 1.0,
  }) : _rotationX = initialRotationX,
       _rotationY = initialRotationY,
       _scale = initialScale;

  double _rotationX;
  double _rotationY;
  double _scale;

  /// Minimum scale (zoom out limit)
  static const double minScale = 1.0;

  /// Maximum scale (zoom in limit)
  static const double maxScale = 50.0;

  /// Maximum tilt angle in radians (prevents flipping over the poles)
  static const double maxTiltAngle = math.pi / 2 - 0.1;

  /// Base rotation sensitivity for drag gestures (at scale 1.0)
  static const double baseRotationSensitivity = 0.005;

  /// Current rotation around the X axis (vertical tilt) in radians
  double get rotationX => _rotationX;

  /// Current rotation around the Y axis (horizontal rotation) in radians
  double get rotationY => _rotationY;

  /// Current scale factor
  double get scale => _scale;

  /// Gets the current projection with the current rotation and scale
  GlobeProjection get projection => GlobeProjection(
    rotationX: _rotationX,
    rotationY: _rotationY,
    scale: _scale,
  );

  /// Updates rotation based on a drag delta.
  ///
  /// [delta] is the drag delta in screen pixels.
  /// Drag moves the globe surface in the same direction as finger movement.
  /// Sensitivity is adjusted based on current scale so that dragging feels
  /// consistent at all zoom levels (finger follows the surface).
  void onDrag(double deltaX, double deltaY) {
    // Adjust sensitivity based on scale - when zoomed in, we need less rotation
    // per pixel to keep the surface following the finger
    final sensitivity = baseRotationSensitivity / _scale;

    // Horizontal drag: drag right = globe surface moves right
    _rotationY += deltaX * sensitivity;

    // Vertical drag: drag up = see more of the north = globe tilts down
    _rotationX += deltaY * sensitivity;
    _rotationX = _rotationX.clamp(-maxTiltAngle, maxTiltAngle);

    // Keep rotationY in reasonable range to avoid floating point issues
    while (_rotationY > math.pi) {
      _rotationY -= 2 * math.pi;
    }
    while (_rotationY < -math.pi) {
      _rotationY += 2 * math.pi;
    }

    notifyListeners();
  }

  /// Updates scale based on a pinch gesture.
  ///
  /// [scaleFactor] is the relative scale change (e.g., 1.1 for 10% zoom in).
  void onScale(double scaleFactor) {
    _scale = (_scale * scaleFactor).clamp(minScale, maxScale);
    notifyListeners();
  }

  /// Sets the scale directly.
  void setScale(double newScale) {
    _scale = newScale.clamp(minScale, maxScale);
    notifyListeners();
  }

  /// Rotates to center on a specific lat/lon location.
  void centerOn(double lat, double lon) {
    _rotationY = -lon * math.pi / 180.0;
    _rotationX = lat * math.pi / 180.0;
    _rotationX = _rotationX.clamp(-maxTiltAngle, maxTiltAngle);
    notifyListeners();
  }

  /// Resets rotation and scale to default values.
  void reset() {
    _rotationX = 0.0;
    _rotationY = 0.0;
    _scale = 1.0;
    notifyListeners();
  }

  /// Animates rotation to a target position.
  ///
  /// This is a simple linear interpolation. For smoother animation,
  /// consider using AnimationController.
  void animateTo({
    double? rotationX,
    double? rotationY,
    double? scale,
    double fraction = 0.2,
  }) {
    if (rotationX != null) {
      _rotationX += (rotationX - _rotationX) * fraction;
    }
    if (rotationY != null) {
      _rotationY += (rotationY - _rotationY) * fraction;
    }
    if (scale != null) {
      _scale += (scale - _scale) * fraction;
      _scale = _scale.clamp(minScale, maxScale);
    }
    notifyListeners();
  }
}
