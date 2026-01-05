import 'dart:math' as math;
import 'dart:ui';

const double _kWebMercatorMaxLatitude = 85.05112878;

class GeoBounds {
  const GeoBounds({
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  bool contains(double lon, double lat) {
    return lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat;
  }

  GeoBounds expand(GeoBounds other) {
    return GeoBounds(
      minLon: math.min(minLon, other.minLon),
      minLat: math.min(minLat, other.minLat),
      maxLon: math.max(maxLon, other.maxLon),
      maxLat: math.max(maxLat, other.maxLat),
    );
  }

  static GeoBounds fromPoints(Iterable<Offset> points) {
    final iterator = points.iterator;
    if (!iterator.moveNext()) {
      throw StateError('GeoBounds requires at least one point.');
    }
    var minLon = iterator.current.dx;
    var maxLon = iterator.current.dx;
    var minLat = iterator.current.dy;
    var maxLat = iterator.current.dy;
    while (iterator.moveNext()) {
      final point = iterator.current;
      minLon = math.min(minLon, point.dx);
      maxLon = math.max(maxLon, point.dx);
      minLat = math.min(minLat, point.dy);
      maxLat = math.max(maxLat, point.dy);
    }
    return GeoBounds(
      minLon: minLon,
      minLat: minLat,
      maxLon: maxLon,
      maxLat: maxLat,
    );
  }
}

class WebMercatorProjection {
  const WebMercatorProjection();

  Offset project(double lon, double lat) {
    final x = (lon + 180.0) / 360.0;
    final clampedLat = lat
        .clamp(-_kWebMercatorMaxLatitude, _kWebMercatorMaxLatitude)
        .toDouble();
    final radians = clampedLat * math.pi / 180.0;
    final sinPhi = math.sin(radians);
    final y = 0.5 - math.log((1 + sinPhi) / (1 - sinPhi)) / (4 * math.pi);
    return Offset(x, y);
  }

  Offset unproject(Offset normalized) {
    return Offset(
      lonFromNormalized(normalized.dx),
      latFromNormalized(normalized.dy),
    );
  }

  double lonFromNormalized(double x) {
    return x * 360.0 - 180.0;
  }

  double latFromNormalized(double y) {
    final t = math.pi * (1 - 2 * y);
    final latRad = math.atan(_sinh(t));
    return latRad * 180.0 / math.pi;
  }
}

bool pointInPolygon(Offset point, List<Offset> polygon) {
  if (polygon.length < 3) {
    return false;
  }
  var inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final current = polygon[i];
    final previous = polygon[j];
    if (_pointOnSegment(point, previous, current)) {
      return true;
    }

    final intersects =
        ((current.dy > point.dy) != (previous.dy > point.dy)) &&
        (point.dx <
            (previous.dx - current.dx) *
                    (point.dy - current.dy) /
                    (previous.dy - current.dy) +
                current.dx);
    if (intersects) {
      inside = !inside;
    }
  }
  return inside;
}

bool _pointOnSegment(Offset point, Offset start, Offset end) {
  const tolerance = 1e-9;
  final cross =
      (point.dy - start.dy) * (end.dx - start.dx) -
      (point.dx - start.dx) * (end.dy - start.dy);
  if (cross.abs() > tolerance) {
    return false;
  }
  final dot =
      (point.dx - start.dx) * (end.dx - start.dx) +
      (point.dy - start.dy) * (end.dy - start.dy);
  if (dot < -tolerance) {
    return false;
  }
  final squaredLength =
      (end.dx - start.dx) * (end.dx - start.dx) +
      (end.dy - start.dy) * (end.dy - start.dy);
  if (dot - squaredLength > tolerance) {
    return false;
  }
  return true;
}

double _sinh(double value) {
  return (math.exp(value) - math.exp(-value)) / 2.0;
}
