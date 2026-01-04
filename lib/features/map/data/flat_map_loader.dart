import 'dart:convert';
import 'dart:io' show GZipCodec;
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

class FlatMapDataset {
  FlatMapDataset(this.geometries);

  final Map<String, CountryGeometry> geometries;
  List<MapPolygon>? _polygonCache;
  Map<String, GeoBounds>? _boundsCache;

  List<MapPolygon> get polygons {
    return _polygonCache ??= _buildPolygonList();
  }

  Map<String, GeoBounds> get boundsByGeometry {
    return _boundsCache ??= {
      for (final entry in geometries.entries) entry.key: entry.value.bounds,
    };
  }

  List<MapPolygon> _buildPolygonList() {
    final entries = geometries.values
        .expand((geometry) => geometry.polygons)
        .toList();
    entries.sort((a, b) {
      final order = a.drawOrder.compareTo(b.drawOrder);
      if (order != 0) {
        return order;
      }
      return a.geometryId.compareTo(b.geometryId);
    });
    return entries;
  }
}

class CountryGeometry {
  CountryGeometry({
    required this.geometryId,
    required this.drawOrder,
    required this.polygons,
    required this.bounds,
  });

  final String geometryId;
  final double drawOrder;
  final List<MapPolygon> polygons;
  final GeoBounds bounds;
}

class FlatMapLoader {
  FlatMapLoader({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle,
      _projection = const WebMercatorProjection();

  final AssetBundle _bundle;
  final WebMercatorProjection _projection;

  static const String _asset50m = 'assets/map/countries_50m.geojson.gz';
  static const String _asset110m = 'assets/map/countries_110m.geojson.gz';

  Future<FlatMapDataset> loadCountries50m() {
    return _loadDataset(_asset50m);
  }

  Future<FlatMapDataset> loadCountries110m() {
    return _loadDataset(_asset110m);
  }

  Future<FlatMapDataset> _loadDataset(String assetPath) async {
    final data = await _bundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final decoded = utf8.decode(GZipCodec().decode(bytes));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final features = (json['features'] as List).cast<Map<String, dynamic>>();

    final builders = <String, _GeometryBuilder>{};
    for (final feature in features) {
      final props = (feature['properties'] as Map?) ?? {};
      final geometryId = (feature['id'] ?? props['geometry_id'])?.toString();
      if (geometryId == null || geometryId.isEmpty) {
        continue;
      }
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry == null) {
        continue;
      }
      final type = geometry['type'] as String?;
      if (type == null) {
        continue;
      }
      final coords = geometry['coordinates'];
      final drawOrder = (props['draw_order'] as num?)?.toDouble() ?? 0;
      final builder = builders.putIfAbsent(
        geometryId,
        () => _GeometryBuilder(
          geometryId: geometryId,
          drawOrder: drawOrder,
          projection: _projection,
        ),
      );
      if (type == 'Polygon') {
        builder.addPolygon(coords as List);
      } else if (type == 'MultiPolygon') {
        for (final polygon in coords as List) {
          builder.addPolygon(polygon as List);
        }
      }
    }

    final geometries = <String, CountryGeometry>{};
    for (final entry in builders.entries) {
      final geometry = entry.value.build();
      if (geometry != null) {
        geometries[entry.key] = geometry;
      }
    }
    return FlatMapDataset(Map.unmodifiable(geometries));
  }
}

class _GeometryBuilder {
  _GeometryBuilder({
    required this.geometryId,
    required this.drawOrder,
    required this.projection,
  });

  final String geometryId;
  final double drawOrder;
  final WebMercatorProjection projection;
  final List<MapPolygon> polygons = [];
  GeoBounds? bounds;

  void addPolygon(List<dynamic> polygonCoords) {
    final result = _convertPolygon(polygonCoords);
    if (result == null) {
      return;
    }
    polygons.add(
      MapPolygon(
        geometryId: geometryId,
        drawOrder: drawOrder,
        rings: result.rings,
      ),
    );
    bounds = bounds == null ? result.bounds : bounds!.expand(result.bounds);
  }

  CountryGeometry? build() {
    if (polygons.isEmpty || bounds == null) {
      return null;
    }
    return CountryGeometry(
      geometryId: geometryId,
      drawOrder: drawOrder,
      polygons: List.unmodifiable(polygons),
      bounds: bounds!,
    );
  }

  _PolygonConversionResult? _convertPolygon(List<dynamic> rings) {
    final transformed = <List<Offset>>[];
    final lonLatPoints = <Offset>[];
    for (final ring in rings) {
      final parsedRing = <Offset>[];
      for (final point in ring as List) {
        final lon = (point[0] as num).toDouble();
        final lat = (point[1] as num).toDouble();
        lonLatPoints.add(Offset(lon, lat));
        parsedRing.add(projection.project(lon, lat));
      }
      if (parsedRing.length < 3) {
        continue;
      }
      if (_arePointsEqual(parsedRing.first, parsedRing.last)) {
        parsedRing.removeLast();
      }
      if (parsedRing.length < 3) {
        continue;
      }
      transformed.add(parsedRing);
    }
    if (transformed.isEmpty || lonLatPoints.isEmpty) {
      return null;
    }
    final bounds = GeoBounds.fromPoints(lonLatPoints);
    return _PolygonConversionResult(rings: transformed, bounds: bounds);
  }
}

class _PolygonConversionResult {
  const _PolygonConversionResult({required this.rings, required this.bounds});

  final List<List<Offset>> rings;
  final GeoBounds bounds;
}

bool _arePointsEqual(Offset a, Offset b) {
  const threshold = 1e-9;
  return (a.dx - b.dx).abs() < threshold && (a.dy - b.dy).abs() < threshold;
}
