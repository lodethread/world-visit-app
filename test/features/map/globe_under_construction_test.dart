import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/features/map/widgets/globe_under_construction.dart';

void main() {
  testWidgets('under construction screen shows info and can exit', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlatMapUnderConstruction(onExit: () => tapped = true),
        ),
      ),
    );

    expect(find.text('Flat Map (Under construction)'), findsOneWidget);
    expect(find.textContaining('平面地図は現在調整中'), findsOneWidget);

    await tester.tap(find.text('Globeに切替'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
