import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';

void main() {
  sqfliteFfiInit();

  test(
    'tag repository normalizes name_norm and reuses existing tags',
    () async {
      final db = await AppDatabase(
        factory: databaseFactoryFfi,
      ).open(path: inMemoryDatabasePath);
      final repo = TagRepository(db);

      final tag1 = await repo.getOrCreateByName('Café');
      final tag2 = await repo.getOrCreateByName('Cafe');

      expect(tag1.tagId, tag2.tagId);
      expect(tag1.nameNorm, 'cafe');
    },
  );
}
