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

  // Star colors
  static const Color _starWhite = Color(0xFFFFFFFF);
  static const Color _starGold = Color(0xFFFFD700);
  static const Color _starBlue = Color(0xFFADD8E6);

  // Pre-generated star positions (seeded for consistency)
  static final List<_Star> _stars = _generateStars(150);

  static List<_Star> _generateStars(int count) {
    final random = Random(42); // Fixed seed for consistent star positions
    final stars = <_Star>[];
    for (var i = 0; i < count; i++) {
      stars.add(
        _Star(
          // Normalized position (0-1)
          x: random.nextDouble(),
          y: random.nextDouble(),
          // Size varies from tiny to small
          size: 0.5 + random.nextDouble() * 2.0,
          // Phase offset for twinkling
          phaseOffset: random.nextDouble() * 2 * pi,
          // Brightness base (some stars are naturally brighter)
          baseBrightness: 0.3 + random.nextDouble() * 0.7,
          // Color type (0 = white, 1 = gold, 2 = blue)
          colorType: random.nextInt(10) < 7 ? 0 : (random.nextInt(2) + 1),
        ),
      );
    }
    return stars;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 * 0.9;

    // Draw starfield background first
    _drawStarfield(canvas, size, center, radius);

    _drawOcean(canvas, center, radius);
    _drawPolarCaps(canvas, center, radius);
    _drawCountries(canvas, center, radius);
  }

  void _drawStarfield(Canvas canvas, Size size, Offset center, double radius) {
    final starPaint = Paint()..style = PaintingStyle.fill;
    final globeRadius = radius * projection.scale;

    for (final star in _stars) {
      // Convert normalized position to screen coordinates
      final starX = star.x * size.width;
      final starY = star.y * size.height;
      final starPos = Offset(starX, starY);

      // Skip stars that would be behind the globe
      final distanceFromCenter = (starPos - center).distance;
      if (distanceFromCenter < globeRadius + 5) {
        continue;
      }

      // Calculate twinkling brightness
      final twinklePhase = sparklePhase + star.phaseOffset;
      final twinkle = (sin(twinklePhase * 2) + 1) / 2; // 0.0 to 1.0
      final brightness = star.baseBrightness * (0.4 + twinkle * 0.6);

      // Get star color based on type
      Color baseColor;
      switch (star.colorType) {
        case 1:
          baseColor = _starGold;
          break;
        case 2:
          baseColor = _starBlue;
          break;
        default:
          baseColor = _starWhite;
      }

      starPaint.color = baseColor.withValues(alpha: brightness);

      // Draw star with glow effect for brighter stars
      final starSize = star.size * (0.8 + twinkle * 0.4);

      if (brightness > 0.6) {
        // Draw glow for bright stars
        final glowPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = baseColor.withValues(alpha: brightness * 0.3);
        canvas.drawCircle(starPos, starSize * 2.5, glowPaint);
      }

      // Draw star core
      canvas.drawCircle(starPos, starSize, starPaint);

      // Draw cross sparkle for very bright moments
      if (brightness > 0.8 && twinkle > 0.7) {
        final sparklePaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = baseColor.withValues(alpha: brightness * 0.5)
          ..strokeWidth = 0.5;

        final sparkleLength = starSize * 3;
        canvas.drawLine(
          Offset(starX - sparkleLength, starY),
          Offset(starX + sparkleLength, starY),
          sparklePaint,
        );
        canvas.drawLine(
          Offset(starX, starY - sparkleLength),
          Offset(starX, starY + sparkleLength),
          sparklePaint,
        );
      }
    }
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

/// Data class for a star in the background
class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.phaseOffset,
    required this.baseBrightness,
    required this.colorType,
  });

  final double x;
  final double y;
  final double size;
  final double phaseOffset;
  final double baseBrightness;
  final int colorType;
}
