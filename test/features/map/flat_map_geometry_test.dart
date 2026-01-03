import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/flat_map_geometry.dart';

void main() {
  test('pointInPolygon detects inside/outside', () {
    final polygon = [
      const Offset(0, 0),
      const Offset(1, 0),
      const Offset(1, 1),
      const Offset(0, 1),
    ];
    expect(pointInPolygon(const Offset(0.5, 0.5), polygon), isTrue);
    expect(pointInPolygon(const Offset(1.5, 0.5), polygon), isFalse);
    expect(pointInPolygon(const Offset(0.0, 0.5), polygon), isTrue);
  });
}
