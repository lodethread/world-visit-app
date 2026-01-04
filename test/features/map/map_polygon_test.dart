import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/data/flat_map_loader.dart';

void main() {
  test('MapPolygon respects holes and bounds', () {
    final polygon = MapPolygon(
      geometryId: 'X',
      drawOrder: 10,
      rings: [
        const [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
        const [
          Offset(0.5, 0.5),
          Offset(1.5, 0.5),
          Offset(1.5, 1.5),
          Offset(0.5, 1.5),
        ],
      ],
    );

    expect(polygon.containsPoint(const Offset(0.2, 0.2)), isTrue);
    expect(polygon.containsPoint(const Offset(1, 1)), isFalse);
    expect(polygon.containsPoint(const Offset(3, 3)), isFalse);
  });
}
