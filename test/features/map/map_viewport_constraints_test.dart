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
    // Use extreme values that are definitely outside the clamp range
    final transform = constraints.clamp(
      viewport: viewport,
      scale: minScale / 2,
      translation: const Offset(-99999, -99999),
    );
    expect(transform.scale, minScale);
    // With 3x wide canvas, minTx = viewport.width - (4096 * 3 * scale)
    final totalCanvasWidth = 4096 * 3 * minScale;
    expect(
      transform.translation.dx,
      closeTo(viewport.width - totalCanvasWidth, 1e-6),
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
    // With 3x canvas, centers on the middle world (offset by one world width)
    final singleWorldWidth = 4096 * scale;
    // Expected: (viewport.width - singleWorldWidth) / 2 - singleWorldWidth
    // This centers the middle world in the viewport
    final expectedTx = (viewport.width - singleWorldWidth) / 2 - singleWorldWidth;
    expect(translation.dx, closeTo(expectedTx, 1e-6));
  });
}
