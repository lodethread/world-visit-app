import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:world_visit_app/features/map/flat_map_geometry.dart';

class MapPolygon {
  factory MapPolygon({
    required String geometryId,
    required double drawOrder,
    required List<List<Offset>> rings,
  }) {
    final normalized = _normalizeRings(rings);
    return MapPolygon._internal(
      geometryId: geometryId,
      drawOrder: drawOrder,
      rings: normalized.map((e) => e.points).toList(),
      ringBounds: normalized.map((e) => e.bounds).toList(),
      bounds: _mergeBounds(normalized.map((e) => e.bounds)),
    );
  }

  const MapPolygon._internal({
    required this.geometryId,
    required this.drawOrder,
    required this.rings,
    required this.ringBounds,
    required this.bounds,
  });

  final String geometryId;
  final double drawOrder;
  final List<List<Offset>> rings;
  final List<Rect> ringBounds;
  final Rect bounds;

  bool containsPoint(Offset point) {
    if (rings.isEmpty || !bounds.inflate(1e-6).contains(point)) {
      return false;
    }
    if (!ringBounds.first.inflate(1e-6).contains(point) ||
        !pointInPolygon(point, rings.first)) {
      return false;
    }
    for (int i = 1; i < rings.length; i++) {
      if (ringBounds[i].inflate(1e-6).contains(point) &&
          pointInPolygon(point, rings[i])) {
        return false;
      }
    }
    return true;
  }
}

class _RingData {
  _RingData(this.points, this.bounds);

  final List<Offset> points;
  final Rect bounds;
}

List<_RingData> _normalizeRings(List<List<Offset>> rings) {
  final normalized = <_RingData>[];
  for (final ring in rings) {
    if (ring.length < 3) continue;
    final immutable = List<Offset>.unmodifiable(ring);
    normalized.add(_RingData(immutable, _rectFromRing(immutable)));
  }
  if (normalized.isEmpty) {
    throw StateError('A polygon must contain at least one valid ring.');
  }
  return normalized;
}

Rect _rectFromRing(List<Offset> ring) {
  double minX = ring.first.dx;
  double minY = ring.first.dy;
  double maxX = ring.first.dx;
  double maxY = ring.first.dy;
  for (final point in ring.skip(1)) {
    minX = min(minX, point.dx);
    minY = min(minY, point.dy);
    maxX = max(maxX, point.dx);
    maxY = max(maxY, point.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

Rect _mergeBounds(Iterable<Rect> rects) {
  final iterator = rects.iterator;
  if (!iterator.moveNext()) {
    return Rect.zero;
  }
  var current = iterator.current;
  while (iterator.moveNext()) {
    final next = iterator.current;
    current = Rect.fromLTRB(
      min(current.left, next.left),
      min(current.top, next.top),
      max(current.right, next.right),
      max(current.bottom, next.bottom),
    );
  }
  return current;
}

class FlatMapLoader {
  FlatMapLoader({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  static const String _assetPath = 'assets/map/countries_50m.geojson.gz';

  Future<List<MapPolygon>> load() async {
    final data = await _bundle.load(_assetPath);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final decoded = utf8.decode(GZipCodec().decode(bytes));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final features = (json['features'] as List).cast<Map<String, dynamic>>();
    final polygons = <MapPolygon>[];
    for (final feature in features) {
      final props = (feature['properties'] as Map?) ?? {};
      final geometryId = (feature['id'] ?? props['geometry_id'])?.toString();
      if (geometryId == null || geometryId.isEmpty) continue;
      final drawOrder = (props['draw_order'] as num?)?.toDouble() ?? 0;
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;
      final type = geometry['type'] as String;
      final coords = geometry['coordinates'];
      if (type == 'Polygon') {
        final rings = _convertPolygon(coords as List);
        if (rings.isEmpty) continue;
        polygons.add(
          MapPolygon(
            geometryId: geometryId,
            drawOrder: drawOrder,
            rings: rings,
          ),
        );
      } else if (type == 'MultiPolygon') {
        for (final polygon in coords as List) {
          final rings = _convertPolygon(polygon as List);
          if (rings.isEmpty) continue;
          polygons.add(
            MapPolygon(
              geometryId: geometryId,
              drawOrder: drawOrder,
              rings: rings,
            ),
          );
        }
      }
    }
    polygons.sort((a, b) => a.drawOrder.compareTo(b.drawOrder));
    return polygons;
  }

  List<List<Offset>> _convertPolygon(List<dynamic> rings) {
    final transformed = <List<Offset>>[];
    for (final ring in rings) {
      final rawPoints = (ring as List)
          .map(
            (pt) => _projectLonLat(
              (pt[0] as num).toDouble(),
              (pt[1] as num).toDouble(),
            ),
          )
          .toList();
      if (rawPoints.length < 3) continue;
      if (_arePointsEqual(rawPoints.first, rawPoints.last)) {
        rawPoints.removeLast();
      }
      if (rawPoints.length < 3) continue;
      transformed.add(rawPoints);
    }
    return transformed;
  }

  Offset _projectLonLat(double lon, double lat) {
    final x = (lon + 180.0) / 360.0;
    final clampedLat = lat.clamp(-85.0511, 85.0511);
    final rad = clampedLat * pi / 180.0;
    final y = 0.5 - log((1 + sin(rad)) / (1 - sin(rad))) / (4 * pi);
    return Offset(x, y);
  }

  bool _arePointsEqual(Offset a, Offset b) {
    const threshold = 1e-9;
    return (a.dx - b.dx).abs() < threshold && (a.dy - b.dy).abs() < threshold;
  }
}
