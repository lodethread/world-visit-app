import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/user_setting_repository.dart';

void main() {
  sqfliteFfiInit();

  test('user setting repository saves and restores values', () async {
    final db = await AppDatabase(
      factory: databaseFactoryFfi,
    ).open(path: inMemoryDatabasePath);
    final repo = UserSettingRepository(db);

    expect(await repo.getValue('trips_sort'), isNull);
    await repo.setValue('trips_sort', 'recent');
    expect(await repo.getValue('trips_sort'), 'recent');
    await repo.setValue('trips_sort', 'score');
    expect(await repo.getValue('trips_sort'), 'score');

    await db.close();
  });
}
