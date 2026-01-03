import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/features/map/map_page.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  testWidgets('shows token missing message when MAPBOX_ACCESS_TOKEN is empty', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    expect(find.text('MAPBOX_ACCESS_TOKEN が設定されていません。'), findsOneWidget);
  });
}
