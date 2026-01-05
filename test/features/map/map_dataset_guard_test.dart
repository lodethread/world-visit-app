import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/data/map_dataset_guard.dart';
import 'package:world_visit_app/features/map/data/spatial_index.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';

void main() {
  test('throws when dataset has no geometries', () {
    final dataset = FlatMapDataset(
      geometries: const {},
      spatialIndex: SpatialIndex<String>(),
    );
    expect(
      () => MapDatasetGuard.ensureUsable(dataset, label: 'empty'),
      throwsA(isA<MapDatasetException>()),
    );
  });

  test('passes when dataset contains at least one polygon', () {
    final polygon = MapPolygon(
      geometryId: 'JP',
      drawOrder: 1,
      rings: [
        const [
          Offset(0.1, 0.1),
          Offset(0.2, 0.1),
          Offset(0.2, 0.2),
          Offset(0.1, 0.2),
          Offset(0.1, 0.1),
        ],
      ],
    );
    final geometry = CountryGeometry(
      geometryId: 'JP',
      drawOrder: 1,
      polygons: [polygon],
      bounds: const GeoBounds(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1),
      worldBounds: const Rect.fromLTWH(0.1, 0.1, 0.1, 0.1),
    );
    final spatialIndex = SpatialIndex<String>()
      ..insert(geometry.worldBounds, geometry.geometryId);
    final dataset = FlatMapDataset(
      geometries: {'JP': geometry},
      spatialIndex: spatialIndex,
    );
    expect(
      () => MapDatasetGuard.ensureUsable(dataset, label: 'non-empty'),
      returnsNormally,
    );
  });
}
