import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';

class TripPlaceInfo {
  const TripPlaceInfo({
    required this.code,
    this.nameJa,
    this.nameEn,
    this.maxLevel = 0,
    this.visitCount = 0,
    this.aliases = const <String>[],
  });

  final String code;
  final String? nameJa;
  final String? nameEn;
  final int maxLevel;
  final int visitCount;
  final List<String> aliases;
}

class TripListItem {
  const TripListItem({
    required this.visit,
    required this.place,
    required this.tags,
  });

  final VisitRecord visit;
  final TripPlaceInfo place;
  final List<TagRecord> tags;
}

class TripListLoader {
  TripListLoader(this.db);

  final Database db;

  Future<List<TripListItem>> load() async {
    final visitRows = await db.rawQuery(_visitQuery);
    final aliases = await _loadAliases();
    final visitTags = await _loadVisitTags();

    return visitRows
        .map((row) {
          final visit = VisitRecord.fromMap(row);
          final place = TripPlaceInfo(
            code: visit.placeCode,
            nameJa: row['place_name_ja'] as String?,
            nameEn: row['place_name_en'] as String?,
            maxLevel: (row['place_max_level'] as int?) ?? 0,
            visitCount: (row['place_visit_count'] as int?) ?? 0,
            aliases: aliases[visit.placeCode] ?? const <String>[],
          );
          final tags = visitTags[visit.visitId] ?? const <TagRecord>[];
          return TripListItem(visit: visit, place: place, tags: tags);
        })
        .toList(growable: false);
  }

  Future<Map<String, List<String>>> _loadAliases() async {
    final rows = await db.query(
      'place_alias',
      columns: ['place_code', 'alias'],
    );
    final mapping = <String, List<String>>{};
    for (final row in rows) {
      final code = row['place_code']?.toString();
      final alias = row['alias']?.toString();
      if (code == null || alias == null || alias.isEmpty) {
        continue;
      }
      mapping.putIfAbsent(code, () => <String>[]).add(alias);
    }
    return mapping;
  }

  Future<Map<String, List<TagRecord>>> _loadVisitTags() async {
    final rows = await db.rawQuery('''
SELECT vt.visit_id, t.tag_id, t.name, t.name_norm, t.created_at, t.updated_at
FROM visit_tag vt
INNER JOIN tag t ON t.tag_id = vt.tag_id
ORDER BY t.name ASC
''');
    final mapping = <String, List<TagRecord>>{};
    for (final row in rows) {
      final visitId = row['visit_id'] as String;
      final tag = TagRecord.fromMap(row);
      mapping.putIfAbsent(visitId, () => <TagRecord>[]).add(tag);
    }
    return mapping;
  }
}

const _visitQuery = '''
SELECT
  v.visit_id,
  v.place_code,
  v.title,
  v.start_date,
  v.end_date,
  v.level,
  v.note,
  v.created_at,
  v.updated_at,
  p.name_ja AS place_name_ja,
  p.name_en AS place_name_en,
  ps.max_level AS place_max_level,
  ps.visit_count AS place_visit_count
FROM visit v
LEFT JOIN place p ON p.place_code = v.place_code
LEFT JOIN place_stats ps ON ps.place_code = v.place_code
ORDER BY v.updated_at DESC, v.created_at DESC
''';
