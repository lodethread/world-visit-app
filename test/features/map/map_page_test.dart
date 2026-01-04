import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/features/map/map_page.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('Flat map renders without token', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('経国値'), findsOneWidget);
  });
}
