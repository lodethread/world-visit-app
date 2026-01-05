import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/widgets/map_gesture_layer.dart';

void main() {
  testWidgets(
    'MapGestureLayer triggers long press anywhere on the map surface',
    (tester) async {
      Offset? longPressPosition;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 200,
            child: MapGestureLayer(
              onLongPress: (pos) => longPressPosition = pos,
              child: Container(color: Colors.blue),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(longPressPosition, isNotNull);
      expect(longPressPosition!.dx, closeTo(100, 1));
      expect(longPressPosition!.dy, closeTo(100, 1));
      await gesture.up();
    },
  );

  testWidgets('MapGestureLayer reports tap when movement is small', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 200,
          height: 200,
          child: MapGestureLayer(
            onTap: () => tapped = true,
            child: Container(color: Colors.red),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(50, 80));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    expect(tapped, isTrue);
  });
}
