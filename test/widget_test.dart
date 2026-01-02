// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/app/app.dart';

void main() {
  testWidgets('Main tabs show Map, Trips, and Settings views', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WorldVisitApp());

    expect(find.text('Map'), findsWidgets);
    expect(find.text('Trips'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('Trips'), findsWidgets);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });
}
