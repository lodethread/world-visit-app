import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:world_visit_app/features/map/data/spatial_index.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';

const int _spatialGridCells = 96;

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
      path: _buildPath(normalized),
    );
  }

  const MapPolygon._internal({
    required this.geometryId,
    required this.drawOrder,
    required this.rings,
    required this.ringBounds,
    required this.bounds,
    required this.path,
  });

  final String geometryId;
  final double drawOrder;
  final List<List<Offset>> rings;
  final List<Rect> ringBounds;
  final Rect bounds;
  final Path path;

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

Rect _expandRect(Rect base, Rect addition) {
  return Rect.fromLTRB(
    min(base.left, addition.left),
    min(base.top, addition.top),
    max(base.right, addition.right),
    max(base.bottom, addition.bottom),
  );
}

Path _buildPath(List<_RingData> rings) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final ring in rings) {
    if (ring.points.isEmpty) continue;
    path.moveTo(ring.points.first.dx, ring.points.first.dy);
    for (final point in ring.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
  }
  return path;
}

class FlatMapDataset {
  FlatMapDataset({required this.geometries, required this.spatialIndex});

  final Map<String, CountryGeometry> geometries;
  final SpatialIndex<String> spatialIndex;
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
    required this.worldBounds,
  });

  final String geometryId;
  final double drawOrder;
  final List<MapPolygon> polygons;
  final GeoBounds bounds;
  final Rect worldBounds;
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
    final features = await _decodeFeatures(assetPath);
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
    final spatialIndex = SpatialIndex<String>(cellCount: _spatialGridCells);
    for (final entry in builders.entries) {
      final geometry = entry.value.build();
      if (geometry != null) {
        geometries[entry.key] = geometry;
        spatialIndex.insert(geometry.worldBounds, geometry.geometryId);
      }
    }
    return FlatMapDataset(
      geometries: Map.unmodifiable(geometries),
      spatialIndex: spatialIndex,
    );
  }

  Future<List<Map<String, dynamic>>> _decodeFeatures(String assetPath) async {
    final data = await _bundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final transferable = TransferableTypedData.fromList([bytes]);
    return compute<_DecodeRequest, List<Map<String, dynamic>>>(
      _decodeFeatureCollection,
      _DecodeRequest(transferable),
    );
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
  Rect? worldBounds;

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
    bounds = bounds == null
        ? result.geoBounds
        : bounds!.expand(result.geoBounds);
    worldBounds = worldBounds == null
        ? result.worldBounds
        : _expandRect(worldBounds!, result.worldBounds);
  }

  CountryGeometry? build() {
    if (polygons.isEmpty || bounds == null || worldBounds == null) {
      return null;
    }
    return CountryGeometry(
      geometryId: geometryId,
      drawOrder: drawOrder,
      polygons: List.unmodifiable(polygons),
      bounds: bounds!,
      worldBounds: worldBounds!,
    );
  }

  _PolygonConversionResult? _convertPolygon(List<dynamic> rings) {
    final transformed = <List<Offset>>[];
    final lonLatPoints = <Offset>[];
    Rect? projectedBounds;
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
      final ringBounds = _rectFromRing(parsedRing);
      if (projectedBounds == null) {
        projectedBounds = ringBounds;
      } else {
        projectedBounds = _expandRect(projectedBounds, ringBounds);
      }
      transformed.add(parsedRing);
    }
    if (transformed.isEmpty ||
        lonLatPoints.isEmpty ||
        projectedBounds == null) {
      return null;
    }
    final geoBounds = GeoBounds.fromPoints(lonLatPoints);
    return _PolygonConversionResult(
      rings: transformed,
      geoBounds: geoBounds,
      worldBounds: projectedBounds,
    );
  }
}

class _PolygonConversionResult {
  const _PolygonConversionResult({
    required this.rings,
    required this.geoBounds,
    required this.worldBounds,
  });

  final List<List<Offset>> rings;
  final GeoBounds geoBounds;
  final Rect worldBounds;
}

bool _arePointsEqual(Offset a, Offset b) {
  const threshold = 1e-9;
  return (a.dx - b.dx).abs() < threshold && (a.dy - b.dy).abs() < threshold;
}

class _DecodeRequest {
  const _DecodeRequest(this.data);

  final TransferableTypedData data;
}

List<Map<String, dynamic>> _decodeFeatureCollection(_DecodeRequest request) {
  final materialized = request.data.materialize().asUint8List();
  final decoded = utf8.decode(GZipCodec().decode(materialized));
  final json = jsonDecode(decoded) as Map<String, dynamic>;
  final rawFeatures = (json['features'] as List).cast<Map>();
  return rawFeatures
      .map((feature) => feature.cast<String, dynamic>())
      .toList(growable: false);
}
