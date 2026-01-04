import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, dynamic>> entries;

  setUpAll(() {
    final raw = File('assets/places/place_master.json').readAsStringSync();
    entries = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  });

  test('geometry_id values are unique', () {
    final ids = entries
        .map((e) => e['geometry_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    expect(ids.length, equals(ids.toSet().length));
  });

  test('designated territories map to ISO numeric geometry ids', () {
    const expected = {
      'HK': '344',
      'MO': '446',
      'PR': '630',
      'TW': '158',
      'PS': '275',
      'EH': '732',
      'JP': '392',
      'US': '840',
    };
    final index = {
      for (final entry in entries) entry['place_code'].toString(): entry,
    };
    expected.forEach((code, geometryId) {
      final entry = index[code];
      expect(entry, isNotNull, reason: '$code missing from place master');
      expect(entry?['geometry_id'], geometryId);
      expect(RegExp(r'^\d+$').hasMatch(geometryId), isTrue);
    });
  });

  test('Kosovo keeps XK geometry id', () {
    final entry = entries.singleWhere(
      (element) => element['place_code'] == 'XK',
    );
    expect(entry['geometry_id'], 'XK');
  });
}
