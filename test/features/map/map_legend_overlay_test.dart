import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/widgets/map_legend_overlay.dart';

void main() {
  testWidgets('legend overlay toggles visibility', (tester) async {
    final entries = [
      const MapLegendEntry(
        levelLabel: '0 未踏',
        description: '訪問実績なし',
        color: Colors.blue,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: MapLegendOverlay(entries: entries),
          ),
        ),
      ),
    );

    expect(find.text('Legend'), findsNothing);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Legend'), findsOneWidget);
    expect(find.text('訪問実績なし'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Legend'), findsNothing);
  });
}
