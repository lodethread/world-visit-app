import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/features/import_export/application/import_export_service.dart';
import 'package:world_visit_app/util/normalize.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late ImportExportService service;

  setUp(() async {
    final appDb = AppDatabase(factory: databaseFactoryFfi);
    db = await appDb.open(path: inMemoryDatabasePath);
    await _insertPlace(db, 'AAA');
    service = ImportExportService(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'JSON import skips unknown place_code and inserts valid visit',
    () async {
      final payload = jsonEncode({
        'format': 'keikoku',
        'version': 1,
        'exported_at': '2024-01-01T00:00:00Z',
        'tags': [
          {
            'tag_id': 'tag-1',
            'name': 'History',
            'created_at': 1,
            'updated_at': 1,
          },
        ],
        'visits': [
          {
            'visit_id': 'v-1',
            'place_code': 'AAA',
            'title': 'Valid trip',
            'level': 3,
            'start_date': '2024-02-01',
            'tag_ids': ['tag-1'],
            'created_at': 1,
            'updated_at': 1,
          },
          {
            'visit_id': 'v-2',
            'place_code': 'UNKNOWN',
            'title': 'Should skip',
            'level': 2,
          },
        ],
      });

      final plan = await service.prepareJsonImport(payload);

      expect(plan.preview.visitsTotal, 2);
      expect(plan.preview.valid, 1);
      expect(plan.preview.skipped, 1);
      expect(plan.preview.inserts, 1);
      expect(
        plan.issues.any((issue) => issue.code == 'UNKNOWN_PLACE_CODE'),
        isTrue,
      );

      await service.executeImportPlan(plan);

      final visits = await db.query('visit');
      expect(visits, hasLength(1));
      expect(visits.first['visit_id'], 'v-1');
      final visitTags = await db.query('visit_tag');
      expect(visitTags, hasLength(1));
      expect(visitTags.first['tag_id'], 'tag-1');
    },
  );

  test('JSON import updates existing visit when visit_id matches', () async {
    await db.insert('visit', {
      'visit_id': 'v-up',
      'place_code': 'AAA',
      'title': 'Old title',
      'start_date': '2024-01-10',
      'end_date': null,
      'level': 2,
      'note': null,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('tag', {
      'tag_id': 'obsolete',
      'name': 'Obsolete',
      'name_norm': normalizeText('Obsolete'),
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('visit_tag', {'visit_id': 'v-up', 'tag_id': 'obsolete'});

    final payload = jsonEncode({
      'format': 'keikoku',
      'version': 1,
      'exported_at': '2024-01-01T00:00:00Z',
      'tags': [
        {
          'tag_id': 'tag-new',
          'name': 'Updated',
          'created_at': 1,
          'updated_at': 2,
        },
      ],
      'visits': [
        {
          'visit_id': 'v-up',
          'place_code': 'AAA',
          'title': 'New title',
          'level': 5,
          'tag_ids': ['tag-new'],
          'created_at': 1,
          'updated_at': 3,
        },
      ],
    });

    final plan = await service.prepareJsonImport(payload);
    expect(plan.preview.updates, 1);
    await service.executeImportPlan(plan);

    final visit = (await db.query(
      'visit',
      where: 'visit_id = ?',
      whereArgs: ['v-up'],
    )).first;
    expect(visit['title'], 'New title');
    expect(visit['level'], 5);
    final visitTags = await db.query(
      'visit_tag',
      where: 'visit_id = ?',
      whereArgs: ['v-up'],
    );
    expect(visitTags, hasLength(1));
    expect(visitTags.first['tag_id'], 'tag-new');
  });

  test('CSV import reuses tags via normalized name', () async {
    final nameNorm = normalizeText('Café Spots');
    await db.insert('tag', {
      'tag_id': 'tag-cafe',
      'name': 'Café Spots',
      'name_norm': nameNorm,
      'created_at': 1,
      'updated_at': 1,
    });

    const csv =
        'visit_id,place_code,title,start_date,end_date,level,tags,note,created_at,updated_at\n'
        ',AAA,Coffee Walk,2024-05-01,,3,"Cafe Spots","",,\n';

    final parsed = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(csv);
    expect(parsed.length, 2);

    final plan = await service.prepareCsvImport(csv);
    if (plan.issues.isNotEmpty) {
      fail(
        'issues=${plan.issues.map((e) => '${e.code}:${e.message}').toList()}',
      );
    }
    expect(plan.preview.visitsTotal, 1);
    expect(plan.preview.inserts, 1);
    expect(plan.preview.tagsToCreate, 0);
    expect(plan.preview.valid, 1);
    await service.executeImportPlan(plan);

    final visitTags = await db.query('visit_tag');
    expect(visitTags, hasLength(1));
    expect(visitTags.first['tag_id'], 'tag-cafe');
  });
}

Future<void> _insertPlace(Database db, String placeCode) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('place', {
    'place_code': placeCode,
    'type': 'city',
    'name_ja': 'Place $placeCode',
    'name_en': 'Place $placeCode',
    'is_active': 1,
    'sort_order': 0,
    'geometry_id': null,
    'updated_at': now,
  });
  await db.insert('place_stats', {
    'place_code': placeCode,
    'max_level': 0,
    'visit_count': 0,
    'last_visit_date': null,
    'updated_at': now,
  });
}
