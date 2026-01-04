import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/data/flat_map_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FlatMapLoader parses gzip GeoJSON', () async {
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
    final polygons = await loader.load();
    expect(polygons, hasLength(1));
    expect(polygons.first.geometryId, '392');
    expect(polygons.first.drawOrder, 400);
    expect(polygons.first.rings.single, isNotEmpty);
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
