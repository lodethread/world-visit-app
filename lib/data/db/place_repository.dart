import 'package:sqflite/sqflite.dart';

class PlaceRecord {
  const PlaceRecord({
    required this.placeCode,
    required this.type,
    required this.nameJa,
    required this.nameEn,
    required this.isActive,
    required this.sortOrder,
    this.geometryId,
    required this.updatedAt,
  });

  final String placeCode;
  final String type;
  final String nameJa;
  final String nameEn;
  final bool isActive;
  final int sortOrder;
  final String? geometryId;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return {
      'place_code': placeCode,
      'type': type,
      'name_ja': nameJa,
      'name_en': nameEn,
      'is_active': isActive ? 1 : 0,
      'sort_order': sortOrder,
      'geometry_id': geometryId,
      'updated_at': updatedAt,
    };
  }
}

class PlaceAliasRecord {
  const PlaceAliasRecord({
    required this.placeCode,
    required this.alias,
    required this.aliasNorm,
  });

  final String placeCode;
  final String alias;
  final String aliasNorm;

  Map<String, Object?> toMap() {
    return {'place_code': placeCode, 'alias': alias, 'alias_norm': aliasNorm};
  }
}

class PlaceRepository {
  const PlaceRepository(this.db);

  final Database db;

  Future<void> upsertPlaces(List<PlaceRecord> places) async {
    if (places.isEmpty) return;

    final batch = db.batch();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    for (final place in places) {
      batch.insert(
        'place',
        place.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.insert('place_stats', {
        'place_code': place.placeCode,
        'max_level': 0,
        'visit_count': 0,
        'last_visit_date': null,
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceAliases(
    String placeCode,
    List<PlaceAliasRecord> aliases,
  ) async {
    await db.transaction((txn) async {
      await txn.delete(
        'place_alias',
        where: 'place_code = ?',
        whereArgs: [placeCode],
      );
      if (aliases.isEmpty) {
        return;
      }
      final batch = txn.batch();
      for (final alias in aliases) {
        batch.insert(
          'place_alias',
          alias.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> ensurePlaceStatsRows(Iterable<String> placeCodes) async {
    final codes = placeCodes.toSet();
    if (codes.isEmpty) return;
    final batch = db.batch();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    for (final code in codes) {
      batch.insert('place_stats', {
        'place_code': code,
        'max_level': 0,
        'visit_count': 0,
        'last_visit_date': null,
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}
