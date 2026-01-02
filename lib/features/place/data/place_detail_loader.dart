import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';

class PlaceDetailData {
  const PlaceDetailData({
    required this.nameJa,
    required this.nameEn,
    required this.maxLevel,
    required this.visitCount,
    required this.visits,
  });

  final String nameJa;
  final String nameEn;
  final int maxLevel;
  final int visitCount;
  final List<VisitDetail> visits;
}

class VisitDetail {
  const VisitDetail({required this.visit, required this.tags});

  final VisitRecord visit;
  final List<String> tags;
}

Future<PlaceDetailData?> loadPlaceDetail(Database db, String placeCode) async {
  final placeRows = await db.query(
    'place',
    where: 'place_code = ?',
    whereArgs: [placeCode],
    limit: 1,
  );
  if (placeRows.isEmpty) {
    return null;
  }
  final place = placeRows.first;
  final statsRows = await db.query(
    'place_stats',
    where: 'place_code = ?',
    whereArgs: [placeCode],
    limit: 1,
  );
  final stats = statsRows.isEmpty ? null : statsRows.first;

  final visitRows = await db.query(
    'visit',
    where: 'place_code = ?',
    whereArgs: [placeCode],
    orderBy: "COALESCE(end_date,start_date,'') DESC, updated_at DESC",
  );
  final visitTagRows = await db.query('visit_tag');
  final tagRows = await db.query('tag');
  final tagLookup = {
    for (final row in tagRows)
      row['tag_id'] as String: row['name'] as String,
  };
  final visitTags = <String, List<String>>{};
  for (final row in visitTagRows) {
    visitTags
        .putIfAbsent(row['visit_id'] as String, () => [])
        .add(row['tag_id'] as String);
  }
  final visits = <VisitDetail>[];
  for (final row in visitRows) {
    final visit = VisitRecord.fromMap(row);
    final tags = visitTags[visit.visitId]
            ?.map((id) => tagLookup[id] ?? id)
            .toList() ??
        const [];
    visits.add(VisitDetail(visit: visit, tags: tags));
  }

  return PlaceDetailData(
    nameJa: place['name_ja'] as String,
    nameEn: place['name_en'] as String,
    maxLevel: stats == null ? 0 : stats['max_level'] as int,
    visitCount: stats == null ? 0 : stats['visit_count'] as int,
    visits: visits,
  );
}
