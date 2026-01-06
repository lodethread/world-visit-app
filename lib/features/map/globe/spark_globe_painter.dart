import 'dart:math';

import 'package:flutter/material.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';
import 'package:world_visit_app/features/map/globe/globe_projection.dart';

/// CustomPainter for rendering a 3D globe with sparkling visited countries.
///
/// Visited countries glow in gold/amber with a pulsing effect.
/// Unvisited countries are shown in a muted dark color.
class SparkGlobePainter extends CustomPainter {
  SparkGlobePainter({
    required this.projection,
    required this.dataset,
    required this.levels,
    required this.geometryToPlace,
    this.selectedPlaceCode,
    this.sparklePhase = 0.0,
  });

  final GlobeProjection projection;
  final FlatMapDataset dataset;
  final Map<String, int> levels;
  final Map<String, String> geometryToPlace;
  final String? selectedPlaceCode;
  final double sparklePhase;

  static const _mercator = WebMercatorProjection();

  // Gold/amber colors for visited countries
  static const Color _goldBright = Color(0xFFFFF8DC);
  static const Color _goldDark = Color(0xFFDAA520);

  // Muted color for unvisited countries
  static const Color _unvisitedColor = Color(0xFF2D3748);
  static const Color _unvisitedBorder = Color(0xFF1A202C);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 * 0.9;

    _drawOcean(canvas, center, radius);
    _drawPolarCaps(canvas, center, radius);
    _drawCountries(canvas, center, radius);
  }

  void _drawOcean(Canvas canvas, Offset center, double radius) {
    // Dark ocean with subtle blue tint
    final oceanPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF1A1F2E);

    canvas.drawCircle(center, radius * projection.scale, oceanPaint);

    // Subtle gradient for depth effect
    final gradientPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.05),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.2),
            ],
            stops: const [0.0, 0.5, 1.0],
            center: const Alignment(-0.3, -0.3),
          ).createShader(
            Rect.fromCircle(center: center, radius: radius * projection.scale),
          );
    canvas.drawCircle(center, radius * projection.scale, gradientPaint);
  }

  void _drawPolarCaps(Canvas canvas, Offset center, double radius) {
    final antarcticaLevel = levels['AQ'] ?? 0;
    final antarcticaColor = antarcticaLevel > 0
        ? _getSparklingColor(antarcticaLevel, sparklePhase, 'AQ'.hashCode)
        : _unvisitedColor;

    _drawPolarCap(
      canvas,
      center,
      radius,
      latitude: -90.0,
      edgeLatitude: -85.0,
      color: antarcticaColor,
      isVisited: antarcticaLevel > 0,
    );
  }

  void _drawPolarCap(
    Canvas canvas,
    Offset center,
    double radius, {
    required double latitude,
    required double edgeLatitude,
    required Color color,
    required bool isVisited,
  }) {
    final edgePoints = <Offset>[];
    const numPoints = 72;

    for (var i = 0; i < numPoints; i++) {
      final lon = (i / numPoints) * 360.0 - 180.0;
      final screenPoint = projection.project(edgeLatitude, lon, center, radius);
      if (screenPoint != null) {
        edgePoints.add(screenPoint);
      }
    }

    if (edgePoints.length < 3) return;

    final poleCenter = projection.project(latitude, 0, center, radius);

    final path = Path();
    path.moveTo(edgePoints.first.dx, edgePoints.first.dy);
    for (final point in edgePoints.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();

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
      ..color = isVisited ? _goldDark : _unvisitedBorder
      ..strokeWidth = 1.2;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    if (poleCenter != null) {
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
      ..strokeWidth = 1.0;
    final highlightStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2.5;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(
        Rect.fromCircle(center: center, radius: radius * projection.scale),
      ),
    );

    final selectedPolygons = <MapPolygon>[];

    // First pass: draw all non-selected polygons
    for (final polygon in dataset.polygons) {
      final placeCode = geometryToPlace[polygon.geometryId];
      if (placeCode == null) continue;

      if (placeCode == selectedPlaceCode) {
        selectedPolygons.add(polygon);
        continue;
      }

      final level = levels[placeCode] ?? 0;
      final isVisited = level > 0;

      final globePath = _projectPolygonRings(polygon.rings, center, radius);
      if (globePath == null) continue;

      globePath.fillType = PathFillType.evenOdd;

      if (isVisited) {
        // Sparkling gold for visited countries
        final baseColor = _getSparklingColor(
          level,
          sparklePhase,
          placeCode.hashCode,
        );
        fillPaint.color = baseColor;
        strokePaint.color = _goldDark;
      } else {
        // Muted color for unvisited countries
        fillPaint.color = _unvisitedColor;
        strokePaint.color = _unvisitedBorder;
      }

      canvas.drawPath(globePath, fillPaint);
      canvas.drawPath(globePath, strokePaint);
    }

    // Second pass: draw selected country on top
    if (selectedPlaceCode != null) {
      for (final polygon in selectedPolygons) {
        final level = levels[selectedPlaceCode] ?? 0;
        final isVisited = level > 0;

        final globePath = _projectPolygonRings(polygon.rings, center, radius);
        if (globePath == null) continue;

        globePath.fillType = PathFillType.evenOdd;

        if (isVisited) {
          // Extra bright gold for selected visited country
          fillPaint.color = _goldBright;
        } else {
          // Slightly highlighted muted color for selected unvisited
          fillPaint.color = const Color(0xFF4A5568);
        }

        canvas.drawPath(globePath, fillPaint);
        canvas.drawPath(globePath, highlightStrokePaint);
      }
    }

    canvas.restore();
  }

  /// Gets a sparkling gold color with animated brightness based on level and phase.
  Color _getSparklingColor(int level, double phase, int seed) {
    // Each country sparkles at a different phase based on its hash
    final countryPhase = phase + (seed % 100) / 100.0 * 2 * pi;

    // Sine wave oscillation for sparkle effect
    final sparkle = (sin(countryPhase) + 1) / 2; // 0.0 to 1.0

    // Higher levels = brighter base, more prominent sparkle
    final levelFactor = 0.5 + (level / 5.0) * 0.5; // 0.5 to 1.0

    // Interpolate between gold base and bright gold based on sparkle
    final brightness = 0.7 + sparkle * 0.3 * levelFactor;

    return Color.lerp(_goldDark, _goldBright, brightness)!;
  }

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
        final lon = _mercator.lonFromNormalized(normalized.dx);
        final lat = _mercator.latFromNormalized(normalized.dy);

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
  bool shouldRepaint(covariant SparkGlobePainter oldDelegate) {
    return oldDelegate.projection.rotationX != projection.rotationX ||
        oldDelegate.projection.rotationY != projection.rotationY ||
        oldDelegate.projection.scale != projection.scale ||
        oldDelegate.selectedPlaceCode != selectedPlaceCode ||
        oldDelegate.levels != levels ||
        oldDelegate.sparklePhase != sparklePhase;
  }
}
