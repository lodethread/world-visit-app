import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kosovo feature exists with geometry id XK', () {
    final bytes = File('assets/map/countries_50m.geojson.gz').readAsBytesSync();
    final decoded = utf8.decode(GZipCodec().decode(bytes));
    final data = jsonDecode(decoded) as Map<String, dynamic>;
    final features = (data['features'] as List).cast<Map<String, dynamic>>();
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
}
