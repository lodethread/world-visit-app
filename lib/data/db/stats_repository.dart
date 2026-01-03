import 'package:sqflite/sqflite.dart';

class StatsRepository {
  StatsRepository(this.db);

  final Database db;

  Future<int> totalScore() async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(max_level), 0) AS total FROM place_stats',
    );
    if (rows.isEmpty) {
      return 0;
    }
    return _toInt(rows.first['total']);
  }

  Future<Map<int, int>> levelCounts() async {
    final rows = await db.rawQuery(
      '''
      SELECT max_level AS level, COUNT(*) AS count
      FROM place_stats
      GROUP BY max_level
      '''
          .trim(),
    );
    final counts = {for (var level = 0; level <= 5; level++) level: 0};
    for (final row in rows) {
      final level = _toNullableInt(row['level']);
      final count = _toInt(row['count']);
      if (level != null && counts.containsKey(level)) {
        counts[level] = count;
      }
    }
    return counts;
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  int? _toNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
