import 'package:flutter/material.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart' show WebMercatorProjection;
import 'package:world_visit_app/features/map/globe/globe_controller.dart';
import 'package:world_visit_app/features/map/globe/globe_map_painter.dart';

/// A widget that displays an interactive 3D globe map.
/// 
/// Supports:
/// - Drag to rotate the globe with momentum/inertia
/// - Pinch to zoom in/out
/// - Double tap to zoom in
/// - Long press to select a country
class GlobeMapWidget extends StatefulWidget {
  const GlobeMapWidget({
    super.key,
    required this.dataset,
    required this.levels,
    required this.colorResolver,
    required this.geometryToPlace,
    this.selectedPlaceCode,
    this.onCountrySelected,
    this.onCountryLongPressed,
  });

  final FlatMapDataset dataset;
  final Map<String, int> levels;
  final Color Function(int) colorResolver;
  final Map<String, String> geometryToPlace;
  final String? selectedPlaceCode;
  final ValueChanged<String?>? onCountrySelected;
  final ValueChanged<String>? onCountryLongPressed;

  @override
  State<GlobeMapWidget> createState() => _GlobeMapWidgetState();
}

class _GlobeMapWidgetState extends State<GlobeMapWidget>
    with TickerProviderStateMixin {
  late final GlobeController _controller;
  Offset? _lastFocalPoint;
  double? _lastScale;

  // For inertia/momentum scrolling
  late final AnimationController _inertiaController;
  Offset _velocity = Offset.zero;
  static const double _friction = 0.95; // Friction coefficient for deceleration

  // For double-tap zoom
  late final AnimationController _zoomController;
  double _zoomStartScale = 1.0;
  double _zoomEndScale = 1.0;

  static const _mercator = WebMercatorProjection();
  static const String _kAntarcticaPlaceCode = 'AQ';
  static const double _kAntarcticaLatitudeThreshold = -60.0;

  @override
  void initState() {
    super.initState();
    _controller = GlobeController();
    _controller.addListener(_onControllerChanged);

    // Inertia animation controller
    _inertiaController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(_onInertiaUpdate);

    // Zoom animation controller
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onZoomUpdate);
  }

  @override
  void dispose() {
    _inertiaController.dispose();
    _zoomController.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  void _onInertiaUpdate() {
    if (_velocity.distance < 0.1) {
      _inertiaController.stop();
      return;
    }

    // Apply velocity to rotation
    _controller.onDrag(_velocity.dx, _velocity.dy);

    // Apply friction to slow down
    _velocity = _velocity * _friction;
  }

  void _onZoomUpdate() {
    final t = Curves.easeOutCubic.transform(_zoomController.value);
    final newScale = _zoomStartScale + (_zoomEndScale - _zoomStartScale) * t;
    _controller.setScale(newScale);
  }

  void _onScaleStart(ScaleStartDetails details) {
    // Stop any ongoing inertia
    _inertiaController.stop();
    _velocity = Offset.zero;

    _lastFocalPoint = details.localFocalPoint;
    _lastScale = _controller.scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_lastFocalPoint != null) {
      final delta = details.localFocalPoint - _lastFocalPoint!;
      _controller.onDrag(delta.dx, delta.dy);
      
      // Track velocity for inertia
      _velocity = delta;
      
      _lastFocalPoint = details.localFocalPoint;
    }

    if (_lastScale != null && details.scale != 1.0) {
      final newScale = _lastScale! * details.scale;
      _controller.setScale(newScale);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Start inertia animation if there's enough velocity
    if (_velocity.distance > 2.0) {
      _inertiaController.forward(from: 0.0);
    }

    _lastFocalPoint = null;
    _lastScale = null;
  }

  void _onDoubleTap() {
    // Stop any ongoing animations
    _inertiaController.stop();
    _zoomController.stop();

    // Calculate new zoom level (2x or reset to 1x if already zoomed)
    _zoomStartScale = _controller.scale;
    if (_controller.scale < 2.0) {
      _zoomEndScale = 3.0;
    } else if (_controller.scale < 5.0) {
      _zoomEndScale = 8.0;
    } else {
      _zoomEndScale = 1.0; // Reset zoom
    }

    _zoomController.forward(from: 0.0);
  }

  void _onLongPress(LongPressStartDetails details) {
    final size = context.size;
    if (size == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 * 0.9;

    // Convert screen position to lat/lon
    final latLon = _controller.projection.screenToLatLon(
      details.localPosition,
      center,
      radius,
    );

    if (latLon == null) return; // Outside the globe

    final (lat, lon) = latLon;

    // Find which country contains this point
    final placeCode = _findCountryAtLatLon(lat, lon);
    if (placeCode != null) {
      widget.onCountryLongPressed?.call(placeCode);
    }
  }

  String? _findCountryAtLatLon(double lat, double lon) {
    // Convert lat/lon to normalized Web Mercator coordinates
    final normalized = _mercator.project(lon, lat);

    // Use the spatial index for efficient lookup
    final candidates = widget.dataset.spatialIndex.query(normalized).toList();

    if (candidates.isEmpty) {
      // Fallback: check if we're in Antarctica region
      return _checkAntarcticaFallback(lat);
    }

    // Only return a country if the point is actually inside its polygon
    // This prevents false positives when tapping on ocean areas
    for (final geometryId in candidates) {
      final geometry = widget.dataset.geometries[geometryId];
      if (geometry != null) {
        // Check each polygon in the geometry
        for (final polygon in geometry.polygons) {
          if (polygon.containsPoint(normalized)) {
            return widget.geometryToPlace[geometryId];
          }
        }
      }
    }

    // Fallback: check if we're in Antarctica region (when no polygon match)
    return _checkAntarcticaFallback(lat);
  }

  /// Returns Antarctica place code if latitude is below the threshold
  /// and Antarctica exists in the place data.
  String? _checkAntarcticaFallback(double lat) {
    if (lat > _kAntarcticaLatitudeThreshold) {
      return null;
    }
    // Check if Antarctica place code exists in geometryToPlace values
    if (widget.geometryToPlace.containsValue(_kAntarcticaPlaceCode)) {
      return _kAntarcticaPlaceCode;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      onDoubleTap: _onDoubleTap,
      onLongPressStart: _onLongPress,
      child: Container(
        color: const Color(0xFF1D2125), // Atlassian dark background
        child: CustomPaint(
          painter: GlobeMapPainter(
            projection: _controller.projection,
            dataset: widget.dataset,
            levels: widget.levels,
            colorResolver: widget.colorResolver,
            geometryToPlace: widget.geometryToPlace,
            selectedPlaceCode: widget.selectedPlaceCode,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}
