import 'package:sqflite/sqflite.dart';

class UserSettingRepository {
  const UserSettingRepository(this.db);

  final Database db;

  Future<void> setValue(String key, String value) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('user_setting', {
      'key': key,
      'value': value,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getValue(String key) async {
    final rows = await db.query(
      'user_setting',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = rows.first['value'];
    return value?.toString();
  }
}
