import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/lod_resolver.dart';

void main() {
  group('MapLodResolver', () {
    test('prefers 110m when lonSpan is wide', () {
      const resolver = MapLodResolver();
      expect(resolver.resolve(180, MapLod.fine50m), MapLod.coarse110m);
    });

    test('prefers 50m when lonSpan is narrow', () {
      const resolver = MapLodResolver();
      expect(resolver.resolve(45, MapLod.coarse110m), MapLod.fine50m);
    });

    test('applies hysteresis between 90° and 100°', () {
      const resolver = MapLodResolver();
      expect(resolver.resolve(95, MapLod.coarse110m), MapLod.coarse110m);
      expect(resolver.resolve(95, MapLod.fine50m), MapLod.fine50m);
    });
  });
}
