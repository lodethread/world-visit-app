import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    final appDatabase = AppDatabase(factory: databaseFactoryFfi);
    db = await appDatabase.open(path: inMemoryDatabasePath);
    await _insertPlace(db, 'AAA');
  });

  tearDown(() async {
    await db.close();
  });

  test('insert updates place_stats counters and max level', () async {
    await _insertVisit(
      db,
      visitId: 'visit-1',
      placeCode: 'AAA',
      level: 4,
      startDate: '2024-01-10',
    );

    final stats = await _fetchPlaceStats(db, 'AAA');
    expect(stats['visit_count'], 1);
    expect(stats['max_level'], 4);
    expect(stats['last_visit_date'], '2024-01-10');
  });

  test('delete lowers max_level when top visit removed', () async {
    await _insertVisit(
      db,
      visitId: 'visit-2',
      placeCode: 'AAA',
      level: 2,
      startDate: '2024-02-01',
    );
    await _insertVisit(
      db,
      visitId: 'visit-3',
      placeCode: 'AAA',
      level: 5,
      startDate: '2024-03-01',
    );

    await db.delete('visit', where: 'visit_id = ?', whereArgs: ['visit-3']);

    final stats = await _fetchPlaceStats(db, 'AAA');
    expect(stats['visit_count'], 1);
    expect(stats['max_level'], 2);
    expect(stats['last_visit_date'], '2024-02-01');
  });

  test('update moving visit to another place updates both rows', () async {
    await _insertPlace(db, 'BBB');
    await _insertVisit(
      db,
      visitId: 'visit-4',
      placeCode: 'AAA',
      level: 3,
      startDate: '2024-04-05',
    );

    await db.update(
      'visit',
      {
        'place_code': 'BBB',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'visit_id = ?',
      whereArgs: ['visit-4'],
    );

    final statsA = await _fetchPlaceStats(db, 'AAA');
    final statsB = await _fetchPlaceStats(db, 'BBB');
    expect(statsA['visit_count'], 0);
    expect(statsA['max_level'], 0);
    expect(statsA['last_visit_date'], isNull);
    expect(statsB['visit_count'], 1);
    expect(statsB['max_level'], 3);
    expect(statsB['last_visit_date'], '2024-04-05');
  });
}

Future<void> _insertPlace(Database db, String placeCode) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  await db.insert('place', {
    'place_code': placeCode,
    'type': 'city',
    'name_ja': 'テスト$placeCode',
    'name_en': 'Test $placeCode',
    'is_active': 1,
    'sort_order': 0,
    'geometry_id': null,
    'updated_at': timestamp,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('place_stats', {
    'place_code': placeCode,
    'max_level': 0,
    'visit_count': 0,
    'last_visit_date': null,
    'updated_at': timestamp,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

Future<void> _insertVisit(
  Database db, {
  required String visitId,
  required String placeCode,
  required int level,
  required String startDate,
}) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  await db.insert('visit', {
    'visit_id': visitId,
    'place_code': placeCode,
    'title': 'Trip $visitId',
    'start_date': startDate,
    'end_date': null,
    'level': level,
    'note': null,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}

Future<Map<String, Object?>> _fetchPlaceStats(
  Database db,
  String placeCode,
) async {
  final result = await db.query(
    'place_stats',
    where: 'place_code = ?',
    whereArgs: [placeCode],
    limit: 1,
  );
  if (result.isEmpty) {
    throw StateError('place_stats missing for $placeCode');
  }
  return result.first;
}
