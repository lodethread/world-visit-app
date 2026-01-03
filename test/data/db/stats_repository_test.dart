import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/stats_repository.dart';

void main() {
  sqfliteFfiInit();

  group('StatsRepository', () {
    test('aggregates total score and level counts from place_stats', () async {
      final db = await _openInMemory();
      addTearDown(() => db.close());

      for (final code in ['JP', 'US', 'TW', 'BR', 'FR']) {
        await _insertPlace(db, code);
      }

      await _insertStats(db, 'JP', 5);
      await _insertStats(db, 'US', 3);
      await _insertStats(db, 'TW', 1);
      await _insertStats(db, 'BR', 0);
      await _insertStats(db, 'FR', 3);

      final repository = StatsRepository(db);

      expect(await repository.totalScore(), 12);
      final counts = await repository.levelCounts();
      expect(counts[0], 1);
      expect(counts[1], 1);
      expect(counts[2], 0);
      expect(counts[3], 2);
      expect(counts[4], 0);
      expect(counts[5], 1);
    });
  });
}

Future<Database> _openInMemory() {
  final appDb = AppDatabase(factory: databaseFactoryFfi);
  return appDb.open(path: inMemoryDatabasePath);
}

Future<void> _insertPlace(Database db, String placeCode) {
  return db.insert('place', {
    'place_code': placeCode,
    'type': 'country',
    'name_ja': 'name_$placeCode',
    'name_en': 'name_$placeCode',
    'is_active': 1,
    'sort_order': 0,
    'geometry_id': null,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}

Future<void> _insertStats(Database db, String placeCode, int level) {
  return db.insert('place_stats', {
    'place_code': placeCode,
    'max_level': level,
    'visit_count': level == 0 ? 0 : 1,
    'last_visit_date': null,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}
