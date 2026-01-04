import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/data/flat_map_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FlatMapLoader parses gzip GeoJSON dataset', () async {
    final geojson = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'id': '392',
          'properties': {'draw_order': 400},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [130.0, 30.0],
                [131.0, 30.0],
                [131.0, 31.0],
                [130.0, 31.0],
                [130.0, 30.0],
              ],
            ],
          },
        },
      ],
    });
    final zipped = GZipCodec().encode(utf8.encode(geojson));
    final bundle = _FakeBundle({
      'assets/map/countries_50m.geojson.gz': ByteData.view(
        Uint8List.fromList(zipped).buffer,
      ),
    });

    final loader = FlatMapLoader(bundle: bundle);
    final dataset = await loader.loadCountries50m();
    expect(dataset.polygons, hasLength(1));
    final polygon = dataset.polygons.first;
    expect(polygon.geometryId, '392');
    expect(polygon.drawOrder, 400);
    expect(polygon.rings.single, isNotEmpty);
    final bounds = dataset.boundsByGeometry['392'];
    expect(bounds, isNotNull);
    expect(bounds!.minLon, closeTo(130.0, 1e-6));
    final Rect worldBounds = dataset.geometries['392']!.worldBounds;
    final hits = dataset.spatialIndex.query(worldBounds.center).toList();
    expect(hits, contains('392'));
  });
}

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.data);
  final Map<String, ByteData> data;

  @override
  Future<ByteData> load(String key) async {
    final value = data[key];
    if (value == null) throw StateError('Missing $key');
    return value;
  }
}
