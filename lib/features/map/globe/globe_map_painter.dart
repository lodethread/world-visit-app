import 'package:flutter/material.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';
import 'package:world_visit_app/features/map/globe/globe_projection.dart';

/// CustomPainter for rendering a 3D globe with country polygons.
class GlobeMapPainter extends CustomPainter {
  GlobeMapPainter({
    required this.projection,
    required this.dataset,
    required this.levels,
    required this.colorResolver,
    required this.geometryToPlace,
    this.selectedPlaceCode,
  });

  final GlobeProjection projection;
  final FlatMapDataset dataset;
  final Map<String, int> levels;
  final Color Function(int) colorResolver;
  final Map<String, String> geometryToPlace;
  final String? selectedPlaceCode;

  static const _mercator = WebMercatorProjection();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 * 0.9; // 90% of available space

    // Draw ocean background (the globe sphere)
    _drawOcean(canvas, center, radius);

    // Draw polar caps to fill holes at the poles (Web Mercator limitation)
    _drawPolarCaps(canvas, center, radius);

    // Draw country polygons
    _drawCountries(canvas, center, radius);
  }

  void _drawOcean(Canvas canvas, Offset center, double radius) {
    final oceanPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF3D5A80); // Atlassian-style ocean color

    // Draw the visible hemisphere as a filled circle
    canvas.drawCircle(center, radius * projection.scale, oceanPaint);

    // Optional: Add a subtle gradient for 3D effect
    final gradientPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.15),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.1),
            ],
            stops: const [0.0, 0.5, 1.0],
            center: const Alignment(-0.3, -0.3),
          ).createShader(
            Rect.fromCircle(center: center, radius: radius * projection.scale),
          );
    canvas.drawCircle(center, radius * projection.scale, gradientPaint);
  }

  /// Draws polar caps to fill holes at the poles.
  /// Web Mercator projection cannot represent latitudes beyond ~85 degrees,
  /// so we manually draw caps at the poles.
  void _drawPolarCaps(Canvas canvas, Offset center, double radius) {
    // Antarctica color - use the same color as level 0 (unvisited land)
    final antarcticaColor = colorResolver(levels['AQ'] ?? 0);

    // Draw Antarctica cap (South Pole)
    _drawPolarCap(
      canvas,
      center,
      radius,
      latitude: -90.0,
      edgeLatitude: -85.0,
      color: antarcticaColor,
    );
  }

  /// Draws a circular polar cap.
  void _drawPolarCap(
    Canvas canvas,
    Offset center,
    double radius, {
    required double latitude,
    required double edgeLatitude,
    required Color color,
  }) {
    // Generate points around the edge of the polar cap
    final edgePoints = <Offset>[];
    const numPoints = 72; // One point every 5 degrees

    for (var i = 0; i < numPoints; i++) {
      final lon = (i / numPoints) * 360.0 - 180.0;
      final screenPoint = projection.project(edgeLatitude, lon, center, radius);
      if (screenPoint != null) {
        edgePoints.add(screenPoint);
      }
    }

    // Only draw if we have enough visible points
    if (edgePoints.length < 3) return;

    // Also project the pole center
    final poleCenter = projection.project(latitude, 0, center, radius);

    final path = Path();
    path.moveTo(edgePoints.first.dx, edgePoints.first.dy);
    for (final point in edgePoints.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();

    // Clip to globe
    canvas.save();
    canvas.clipPath(
      Path()..addOval(
        Rect.fromCircle(center: center, radius: radius * projection.scale),
      ),
    );

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF2a2a2a)
      ..strokeWidth = 1.2;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    // If the pole center is visible, fill the area properly
    if (poleCenter != null) {
      // Draw a filled polygon from center to edge points
      final polePath = Path();
      polePath.moveTo(poleCenter.dx, poleCenter.dy);
      for (final point in edgePoints) {
        polePath.lineTo(point.dx, point.dy);
      }
      polePath.close();
      canvas.drawPath(polePath, fillPaint);
    }

    canvas.restore();
  }

  void _drawCountries(Canvas canvas, Offset center, double radius) {
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color =
          const Color(0xFF2a2a2a) // Darker, more visible border
      ..strokeWidth = 1.2; // Thicker border for visibility
    final highlightStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2.5;

    // Clip to the globe circle
    canvas.save();
    canvas.clipPath(
      Path()..addOval(
        Rect.fromCircle(center: center, radius: radius * projection.scale),
      ),
    );

    // Collect selected country's polygons to draw them last (on top)
    final selectedPolygons = <MapPolygon>[];

    // First pass: draw all non-selected polygons
    for (final polygon in dataset.polygons) {
      final placeCode = geometryToPlace[polygon.geometryId];
      if (placeCode == null) continue;

      // Skip selected country in first pass - will draw it last
      if (placeCode == selectedPlaceCode) {
        selectedPolygons.add(polygon);
        continue;
      }

      final level = levels[placeCode] ?? 0;
      final baseColor = colorResolver(level);

      // Convert the polygon rings to globe coordinates
      final globePath = _projectPolygonRings(polygon.rings, center, radius);
      if (globePath == null) continue;

      // Use evenOdd fill to handle holes correctly (e.g., Antarctica)
      globePath.fillType = PathFillType.evenOdd;

      fillPaint.color = baseColor;
      canvas.drawPath(globePath, fillPaint);
      canvas.drawPath(globePath, strokePaint);
    }

    // Second pass: draw selected country on top so border is fully visible
    if (selectedPlaceCode != null) {
      for (final polygon in selectedPolygons) {
        final level = levels[selectedPlaceCode] ?? 0;
        final baseColor = colorResolver(level);
        final highlightColor = Color.lerp(baseColor, Colors.white, 0.4)!;

        final globePath = _projectPolygonRings(polygon.rings, center, radius);
        if (globePath == null) continue;

        globePath.fillType = PathFillType.evenOdd;
        fillPaint.color = highlightColor;

        canvas.drawPath(globePath, fillPaint);
        canvas.drawPath(globePath, highlightStrokePaint);
      }
    }

    canvas.restore();
  }

  /// Converts polygon rings (in normalized 0-1 coordinates) to a globe-projected Path.
  /// Uses original vertices for maximum detail.
  /// Returns null if the polygon is entirely on the back side of the globe.
  Path? _projectPolygonRings(
    List<List<Offset>> rings,
    Offset center,
    double radius,
  ) {
    final globePath = Path();
    var hasVisiblePoints = false;

    for (final ring in rings) {
      final contourPoints = <Offset>[];

      for (final normalized in ring) {
        // Convert from Web Mercator normalized coords to lat/lon
        final lon = _mercator.lonFromNormalized(normalized.dx);
        final lat = _mercator.latFromNormalized(normalized.dy);

        // Project to globe
        final screenPoint = projection.project(lat, lon, center, radius);
        if (screenPoint != null) {
          contourPoints.add(screenPoint);
          hasVisiblePoints = true;
        }
      }

      if (contourPoints.length >= 3) {
        globePath.moveTo(contourPoints.first.dx, contourPoints.first.dy);
        for (var i = 1; i < contourPoints.length; i++) {
          globePath.lineTo(contourPoints[i].dx, contourPoints[i].dy);
        }
        globePath.close();
      }
    }

    return hasVisiblePoints ? globePath : null;
  }

  @override
  bool shouldRepaint(covariant GlobeMapPainter oldDelegate) {
    return oldDelegate.projection.rotationX != projection.rotationX ||
        oldDelegate.projection.rotationY != projection.rotationY ||
        oldDelegate.projection.scale != projection.scale ||
        oldDelegate.selectedPlaceCode != selectedPlaceCode ||
        oldDelegate.levels != levels;
  }
}
