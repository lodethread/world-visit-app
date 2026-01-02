import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/place/data/place_detail_loader.dart';

void main() {
  sqfliteFfiInit();

  test('loadPlaceDetail returns stats and visits', () async {
    final db = await AppDatabase(
      factory: databaseFactoryFfi,
    ).open(path: inMemoryDatabasePath);
    await db.insert('place', {
      'place_code': 'JP',
      'type': 'country',
      'name_ja': '日本',
      'name_en': 'Japan',
      'is_active': 1,
      'sort_order': 0,
      'geometry_id': 'JP',
      'updated_at': 0,
    });
    await db.insert('place_stats', {
      'place_code': 'JP',
      'max_level': 5,
      'visit_count': 1,
      'last_visit_date': '2024-01-01',
      'updated_at': 0,
    });
    final visitRepo = VisitRepository(db);
    final tagRepo = TagRepository(db);
    final visit = await visitRepo.createVisit(
      placeCode: 'JP',
      title: 'Tokyo',
      level: 4,
      startDate: '2024-01-01',
      endDate: '2024-01-02',
    );
    final tag = await tagRepo.getOrCreateByName('Food');
    await visitRepo.setTagsForVisit(visit.visitId, [tag.tagId]);

    final detail = await loadPlaceDetail(db, 'JP');
    expect(detail, isNotNull);
    expect(detail!.maxLevel, 4);
    expect(detail.visitCount, 1);
    expect(detail.visits.single.visit.title, 'Tokyo');
    expect(detail.visits.single.tags, ['Food']);
    await db.close();
  });

  test('loadPlaceDetail returns null for missing place', () async {
    final db = await AppDatabase(
      factory: databaseFactoryFfi,
    ).open(path: inMemoryDatabasePath);
    final detail = await loadPlaceDetail(db, 'XX');
    expect(detail, isNull);
    await db.close();
  });
}
