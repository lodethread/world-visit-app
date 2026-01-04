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

  test('WebMercator projection round trip stays accurate', () {
    const projection = WebMercatorProjection();
    const points = [
      Offset(-122.4194, 37.7749),
      Offset(139.6917, 35.6895),
      Offset(0, 0),
      Offset(77.2090, 28.6139),
    ];
    for (final point in points) {
      final normalized = projection.project(point.dx, point.dy);
      final restored = projection.unproject(normalized);
      expect(restored.dx, closeTo(point.dx, 1e-6));
      expect(restored.dy, closeTo(point.dy, 1e-6));
    }
  });
}
