import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/data/spatial_index.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';
import 'package:world_visit_app/features/map/map_page.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Flat map renders once place data is available', (tester) async {
    final db = await tester.runAsync(_preparePlaceDatabase);
    expect(db, isNotNull);
    final dataset = _fakeDataset();
    await tester.pumpWidget(
      MaterialApp(
        home: MapPage(
          mapLoader: _FakeFlatMapLoader(dataset),
          openDatabase: () async => db!,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.textContaining('経国値'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Fallback notice appears when polygons cannot be filled', (
    tester,
  ) async {
    final db = await tester.runAsync(
      () => _preparePlaceDatabase(includePlace: false),
    );
    expect(db, isNotNull);
    final dataset = _fakeDataset();
    await tester.pumpWidget(
      MaterialApp(
        home: MapPage(
          mapLoader: _FakeFlatMapLoader(dataset),
          openDatabase: () async => db!,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final state = tester.state(find.byType(MapPage)) as dynamic;
    var attempts = 0;
    while (attempts < 30 && state.debugRenderState is! MapRenderReady) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      attempts += 1;
    }
    expect(state.debugRenderState is MapRenderReady, isTrue);
    expect(state.hasDrawablePolygons as bool, isFalse);
  });

  testWidgets('Error UI appears when dataset load fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapPage(
          mapLoader: _FailingFlatMapLoader(),
          openDatabase: _unusedDatabase,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('地図データの読み込みに失敗しました'), findsOneWidget);
    expect(find.text('再読み込み'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<Database> _unusedDatabase() {
  throw StateError('openDatabase should not be called when loader fails');
}

Future<Database> _preparePlaceDatabase({
  String geometryId = '392',
  bool includePlace = true,
}) async {
  final appDb = AppDatabase(factory: databaseFactoryFfi);
  final tempPath =
      '${Directory.systemTemp.path}/map_page_test_${DateTime.now().microsecondsSinceEpoch}.db';
  final db = await appDb.open(path: tempPath);
  addTearDown(() async {
    final file = File(tempPath);
    if (await file.exists()) {
      await file.delete();
    }
  });
  if (includePlace) {
    await _insertPlaceWithStats(db, geometryId: geometryId);
  }
  return db;
}

Future<void> _insertPlaceWithStats(
  Database db, {
  String geometryId = '392',
}) async {
  const placeCode = 'JP';
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('place', {
    'place_code': placeCode,
    'type': 'country',
    'name_ja': '日本',
    'name_en': 'Japan',
    'is_active': 1,
    'sort_order': 392,
    'geometry_id': geometryId,
    'updated_at': now,
  });
  await db.insert('place_stats', {
    'place_code': placeCode,
    'max_level': 0,
    'visit_count': 0,
    'last_visit_date': null,
    'updated_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

class _FailingFlatMapLoader extends FlatMapLoader {
  _FailingFlatMapLoader();

  @override
  Future<FlatMapDataset> loadCountries110m() {
    throw StateError('countries_110m missing');
  }

  @override
  Future<FlatMapDataset> loadCountries50m() {
    throw StateError('countries_50m missing');
  }
}

class _FakeFlatMapLoader extends FlatMapLoader {
  _FakeFlatMapLoader(this.dataset);

  final FlatMapDataset dataset;

  @override
  Future<FlatMapDataset> loadCountries110m() async => dataset;

  @override
  Future<FlatMapDataset> loadCountries50m() async => dataset;
}

FlatMapDataset _fakeDataset() {
  final polygon = MapPolygon(
    geometryId: '392',
    drawOrder: 1,
    rings: [
      const [
        Offset(0.2, 0.2),
        Offset(0.3, 0.2),
        Offset(0.3, 0.3),
        Offset(0.2, 0.3),
        Offset(0.2, 0.2),
      ],
    ],
  );
  final geometry = CountryGeometry(
    geometryId: '392',
    drawOrder: 1,
    polygons: [polygon],
    bounds: const GeoBounds(minLon: 130, minLat: 30, maxLon: 140, maxLat: 40),
    worldBounds: const Rect.fromLTRB(0.2, 0.2, 0.3, 0.3),
  );
  final spatialIndex = SpatialIndex<String>()
    ..insert(geometry.worldBounds, geometry.geometryId);
  return FlatMapDataset(
    geometries: {'392': geometry},
    spatialIndex: spatialIndex,
  );
}
