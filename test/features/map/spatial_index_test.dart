import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/data/spatial_index.dart';

void main() {
  test('SpatialIndex narrows hit test candidates', () {
    final index = SpatialIndex<String>(cellCount: 4);
    index.insert(const Rect.fromLTRB(0.0, 0.0, 0.4, 0.4), 'A');
    index.insert(const Rect.fromLTRB(0.6, 0.6, 1.0, 1.0), 'B');

    final hitsA = index.query(const Offset(0.2, 0.2)).toList();
    expect(hitsA, contains('A'));
    expect(hitsA, isNot(contains('B')));

    final hitsB = index.query(const Offset(0.8, 0.8)).toList();
    expect(hitsB, contains('B'));
    expect(hitsB, isNot(contains('A')));
  });
}
