import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';

void main() {
  sqfliteFfiInit();

  test('setTagsForVisit replaces previous tag relations', () async {
    final db = await AppDatabase(
      factory: databaseFactoryFfi,
    ).open(path: inMemoryDatabasePath);
    // seed place and stats row
    await db.insert('place', {
      'place_code': 'JP',
      'type': 'country',
      'name_ja': '日本',
      'name_en': 'Japan',
      'is_active': 1,
      'sort_order': 1,
      'geometry_id': 'JP',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('place_stats', {
      'place_code': 'JP',
      'max_level': 0,
      'visit_count': 0,
      'last_visit_date': null,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    final visitRepo = VisitRepository(db);
    final tagRepo = TagRepository(db);
    final visit = await visitRepo.createVisit(
      placeCode: 'JP',
      title: 'Trip',
      level: 3,
    );
    final tagA = await tagRepo.getOrCreateByName('Food');
    final tagB = await tagRepo.getOrCreateByName('Museum');

    await visitRepo.setTagsForVisit(visit.visitId, [tagA.tagId]);
    var tags = await visitRepo.getTagIdsForVisit(visit.visitId);
    expect(tags, [tagA.tagId]);

    await visitRepo.setTagsForVisit(visit.visitId, [tagB.tagId]);
    tags = await visitRepo.getTagIdsForVisit(visit.visitId);
    expect(tags, [tagB.tagId]);
  });
}
