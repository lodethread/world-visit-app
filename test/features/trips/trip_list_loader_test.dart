import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/features/trips/data/trip_list_loader.dart';
import 'package:world_visit_app/util/normalize.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('TripListLoader returns visits even when stats are missing', () async {
    final handle = await _prepareLoader(
      includeStats: false,
      includeAlias: false,
      includeTags: false,
    );
    final items = await handle.loader.load();
    expect(items, hasLength(1));
    final entry = items.first;
    expect(entry.place.code, 'JP');
    expect(entry.place.maxLevel, 0);
    expect(entry.place.visitCount, 0);
    expect(entry.tags, isEmpty);
    await handle.db.close();
    await File(handle.path).delete();
  });

  test('TripListLoader attaches aliases and tags', () async {
    final handle = await _prepareLoader(
      includeStats: true,
      includeAlias: true,
      includeTags: true,
    );
    final items = await handle.loader.load();
    expect(items.first.place.aliases, contains('Nippon'));
    expect(items.first.tags, hasLength(1));
    expect(items.first.tags.first.name, 'Food');
    await handle.db.close();
    await File(handle.path).delete();
  });
}

class _LoaderHandle {
  const _LoaderHandle({
    required this.db,
    required this.loader,
    required this.path,
  });

  final Database db;
  final TripListLoader loader;
  final String path;
}

Future<_LoaderHandle> _prepareLoader({
  required bool includeStats,
  required bool includeAlias,
  required bool includeTags,
}) async {
  final appDb = AppDatabase(factory: databaseFactoryFfi);
  final tempPath =
      '${Directory.systemTemp.path}/trip_loader_${DateTime.now().microsecondsSinceEpoch}.db';
  final db = await appDb.open(path: tempPath);
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('place', {
    'place_code': 'JP',
    'type': 'country',
    'name_ja': '日本',
    'name_en': 'Japan',
    'is_active': 1,
    'sort_order': 392,
    'geometry_id': '392',
    'updated_at': now,
  });
  await db.insert('visit', {
    'visit_id': 'visit-1',
    'place_code': 'JP',
    'title': 'Tokyo',
    'start_date': null,
    'end_date': null,
    'level': 3,
    'note': null,
    'created_at': now,
    'updated_at': now,
  });
  if (includeStats) {
    await db.insert('place_stats', {
      'place_code': 'JP',
      'max_level': 4,
      'visit_count': 2,
      'last_visit_date': null,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  if (includeAlias) {
    await db.insert('place_alias', {
      'place_code': 'JP',
      'alias': 'Nippon',
      'alias_norm': normalizeText('Nippon'),
    });
  }
  if (includeTags) {
    final tagRepo = TagRepository(db);
    final tag = await tagRepo.getOrCreateByName('Food');
    await db.insert('visit_tag', {'visit_id': 'visit-1', 'tag_id': tag.tagId});
  }
  return _LoaderHandle(db: db, loader: TripListLoader(db), path: tempPath);
}
