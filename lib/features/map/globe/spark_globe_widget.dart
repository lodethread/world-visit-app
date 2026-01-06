import 'dart:math';

import 'package:flutter/material.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart'
    show WebMercatorProjection;
import 'package:world_visit_app/features/map/globe/globe_controller.dart';
import 'package:world_visit_app/features/map/globe/spark_globe_painter.dart';

/// A widget that displays an interactive 3D globe with sparkling visited countries.
///
/// Visited countries (level > 0) are shown in sparkling gold color.
/// Unvisited countries are shown in a muted, subtle color.
class SparkGlobeWidget extends StatefulWidget {
  const SparkGlobeWidget({
    super.key,
    required this.dataset,
    required this.levels,
    required this.geometryToPlace,
    this.selectedPlaceCode,
    this.onCountryLongPressed,
  });

  final FlatMapDataset dataset;
  final Map<String, int> levels;
  final Map<String, String> geometryToPlace;
  final String? selectedPlaceCode;
  final ValueChanged<String>? onCountryLongPressed;

  @override
  State<SparkGlobeWidget> createState() => _SparkGlobeWidgetState();
}

class _SparkGlobeWidgetState extends State<SparkGlobeWidget>
    with TickerProviderStateMixin {
  late final GlobeController _controller;
  Offset? _lastFocalPoint;
  double? _lastScale;

  // For inertia/momentum scrolling
  late final AnimationController _inertiaController;
  Offset _velocity = Offset.zero;
  static const double _friction = 0.95;

  // For double-tap zoom
  late final AnimationController _zoomController;
  double _zoomStartScale = 1.0;
  double _zoomEndScale = 1.0;

  // For sparkle animation
  late final AnimationController _sparkleController;

  static const _mercator = WebMercatorProjection();
  static const String _kAntarcticaPlaceCode = 'AQ';
  static const double _kAntarcticaLatitudeThreshold = -60.0;

  @override
  void initState() {
    super.initState();
    _controller = GlobeController();
    _controller.addListener(_onControllerChanged);

    _inertiaController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(_onInertiaUpdate);

    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onZoomUpdate);

    // Sparkle animation - continuous loop
    _sparkleController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 2000),
          )
          ..addListener(() => setState(() {}))
          ..repeat();
  }

  @override
  void dispose() {
    _inertiaController.dispose();
    _zoomController.dispose();
    _sparkleController.dispose();
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
    _controller.onDrag(_velocity.dx, _velocity.dy);
    _velocity = _velocity * _friction;
  }

  void _onZoomUpdate() {
    final t = Curves.easeOutCubic.transform(_zoomController.value);
    final newScale = _zoomStartScale + (_zoomEndScale - _zoomStartScale) * t;
    _controller.setScale(newScale);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _inertiaController.stop();
    _velocity = Offset.zero;
    _lastFocalPoint = details.localFocalPoint;
    _lastScale = _controller.scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_lastFocalPoint != null) {
      final delta = details.localFocalPoint - _lastFocalPoint!;
      _controller.onDrag(delta.dx, delta.dy);
      _velocity = delta;
      _lastFocalPoint = details.localFocalPoint;
    }

    if (_lastScale != null && details.scale != 1.0) {
      final newScale = _lastScale! * details.scale;
      _controller.setScale(newScale);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_velocity.distance > 2.0) {
      _inertiaController.forward(from: 0.0);
    }
    _lastFocalPoint = null;
    _lastScale = null;
  }

  void _onDoubleTap() {
    _inertiaController.stop();
    _zoomController.stop();

    _zoomStartScale = _controller.scale;
    if (_controller.scale < 2.0) {
      _zoomEndScale = 3.0;
    } else if (_controller.scale < 5.0) {
      _zoomEndScale = 8.0;
    } else {
      _zoomEndScale = 1.0;
    }

    _zoomController.forward(from: 0.0);
  }

  void _onLongPress(LongPressStartDetails details) {
    final size = context.size;
    if (size == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 * 0.9;

    final latLon = _controller.projection.screenToLatLon(
      details.localPosition,
      center,
      radius,
    );

    if (latLon == null) return;

    final (lat, lon) = latLon;
    final placeCode = _findCountryAtLatLon(lat, lon);
    if (placeCode != null) {
      widget.onCountryLongPressed?.call(placeCode);
    }
  }

  String? _findCountryAtLatLon(double lat, double lon) {
    final normalized = _mercator.project(lon, lat);
    final candidates = widget.dataset.spatialIndex.query(normalized).toList();

    if (candidates.isEmpty) {
      return _checkAntarcticaFallback(lat);
    }

    for (final geometryId in candidates) {
      final geometry = widget.dataset.geometries[geometryId];
      if (geometry != null) {
        for (final polygon in geometry.polygons) {
          if (polygon.containsPoint(normalized)) {
            return widget.geometryToPlace[geometryId];
          }
        }
      }
    }

    return _checkAntarcticaFallback(lat);
  }

  String? _checkAntarcticaFallback(double lat) {
    if (lat > _kAntarcticaLatitudeThreshold) {
      return null;
    }
    if (widget.geometryToPlace.containsValue(_kAntarcticaPlaceCode)) {
      return _kAntarcticaPlaceCode;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Compute sparkle phase based on animation value
    final sparklePhase = _sparkleController.value * 2 * pi;

    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      onDoubleTap: _onDoubleTap,
      onLongPressStart: _onLongPress,
      child: Container(
        color: const Color(0xFF0D1117), // Darker background for spark effect
        child: CustomPaint(
          painter: SparkGlobePainter(
            projection: _controller.projection,
            dataset: widget.dataset,
            levels: widget.levels,
            geometryToPlace: widget.geometryToPlace,
            selectedPlaceCode: widget.selectedPlaceCode,
            sparklePhase: sparklePhase,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}
