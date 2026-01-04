import 'dart:convert';
import 'dart:io' show File, GZipCodec;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kosovo feature exists with geometry id XK', () {
    final features = _readFeatures('assets/map/countries_50m.geojson.gz');
    Map<String, dynamic>? kosovo;
    for (final feature in features) {
      if (feature['id'] == 'XK') {
        kosovo = feature;
        break;
      }
    }
    expect(kosovo, isNotNull);
    expect(kosovo!['id'], 'XK');
    expect(kosovo['properties'], isA<Map>());
    expect(kosovo['properties']['name'], anyOf('Kosovo', 'Republic of Kosovo'));
  });

  test('50m asset contains contested territory geometry ids', () {
    final features = _readFeatures('assets/map/countries_50m.geojson.gz');
    const requiredGeometryIds = [
      '344',
      '446',
      '630',
      '158',
      '275',
      '732',
      'XK',
    ];
    for (final geometryId in requiredGeometryIds) {
      Map<String, dynamic>? match;
      for (final feature in features) {
        if (feature['id'].toString() == geometryId) {
          match = feature;
          break;
        }
      }
      expect(match, isNotNull, reason: 'Missing geometry $geometryId');
      expect(
        match!['properties']?['geometry_id']?.toString(),
        geometryId,
        reason: 'geometry_id mismatch for $geometryId',
      );
    }
  });
}

List<Map<String, dynamic>> _readFeatures(String assetPath) {
  final bytes = File(assetPath).readAsBytesSync();
  final decoded = utf8.decode(GZipCodec().decode(bytes));
  final data = jsonDecode(decoded) as Map<String, dynamic>;
  return (data['features'] as List).cast<Map<String, dynamic>>();
}
