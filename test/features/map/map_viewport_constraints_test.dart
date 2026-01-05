import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/map_viewport_constraints.dart';

void main() {
  const constraints = MapViewportConstraints(worldSize: 4096);

  test('coverScale picks the larger axis to cover the screen', () {
    const viewport = Size(800, 600);
    final scale = constraints.coverScale(viewport);
    expect(scale, viewport.width / 4096);

    const tallViewport = Size(600, 1200);
    final tallScale = constraints.coverScale(tallViewport);
    expect(tallScale, tallViewport.height / 4096);
  });

  test('clamp enforces minimum scale and translation bounds', () {
    const viewport = Size(600, 1400);
    final minScale = constraints.coverScale(viewport);
    final transform = constraints.clamp(
      viewport: viewport,
      scale: minScale / 2,
      translation: const Offset(-2000, -2000),
    );
    expect(transform.scale, minScale);
    expect(
      transform.translation.dx,
      closeTo(viewport.width - 4096 * minScale, 1e-6),
    );
    expect(
      transform.translation.dy,
      closeTo(viewport.height - 4096 * minScale, 1e-6),
    );
  });

  test('centeredTranslation recenters the world', () {
    const viewport = Size(1080, 720);
    final scale = constraints.coverScale(viewport);
    final translation = constraints.centeredTranslation(
      viewport: viewport,
      scale: scale,
    );
    expect(translation.dx <= 0, isTrue);
    expect(translation.dy <= 0, isTrue);
    final worldWidth = 4096 * scale;
    expect(translation.dx, closeTo((viewport.width - worldWidth) / 2, 1e-6));
  });
}
