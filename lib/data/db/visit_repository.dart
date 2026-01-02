import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class VisitRecord {
  const VisitRecord({
    required this.visitId,
    required this.placeCode,
    required this.title,
    this.startDate,
    this.endDate,
    required this.level,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String visitId;
  final String placeCode;
  final String title;
  final String? startDate;
  final String? endDate;
  final int level;
  final String? note;
  final int createdAt;
  final int updatedAt;

  VisitRecord copyWith({
    String? visitId,
    String? placeCode,
    String? title,
    String? startDate,
    String? endDate,
    int? level,
    String? note,
    int? createdAt,
    int? updatedAt,
  }) {
    return VisitRecord(
      visitId: visitId ?? this.visitId,
      placeCode: placeCode ?? this.placeCode,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      level: level ?? this.level,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'visit_id': visitId,
      'place_code': placeCode,
      'title': title,
      'start_date': startDate,
      'end_date': endDate,
      'level': level,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory VisitRecord.fromMap(Map<String, Object?> row) {
    return VisitRecord(
      visitId: row['visit_id'] as String,
      placeCode: row['place_code'] as String,
      title: row['title'] as String,
      startDate: row['start_date'] as String?,
      endDate: row['end_date'] as String?,
      level: row['level'] as int,
      note: row['note'] as String?,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}

class VisitRepository {
  VisitRepository(this.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Database db;
  final Uuid _uuid;

  Future<VisitRecord> createVisit({
    required String placeCode,
    required String title,
    String? startDate,
    String? endDate,
    required int level,
    String? note,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final visitId = _uuid.v4();
    final record = VisitRecord(
      visitId: visitId,
      placeCode: placeCode,
      title: title,
      startDate: startDate,
      endDate: endDate,
      level: level,
      note: note,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await db.insert('visit', record.toMap());
    return record;
  }

  Future<void> updateVisit(VisitRecord record) async {
    await db.update(
      'visit',
      record.toMap(),
      where: 'visit_id = ?',
      whereArgs: [record.visitId],
    );
  }

  Future<void> deleteVisit(String visitId) async {
    await db.delete('visit', where: 'visit_id = ?', whereArgs: [visitId]);
  }

  Future<VisitRecord?> getVisitById(String visitId) async {
    final rows = await db.query(
      'visit',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VisitRecord.fromMap(rows.first);
  }

  Future<List<VisitRecord>> listAll() async {
    final rows = await db.query('visit');
    return rows.map(VisitRecord.fromMap).toList();
  }

  Future<List<VisitRecord>> listByPlace(String placeCode) async {
    final rows = await db.query(
      'visit',
      where: 'place_code = ?',
      whereArgs: [placeCode],
    );
    return rows.map(VisitRecord.fromMap).toList();
  }

  Future<List<String>> getTagIdsForVisit(String visitId) async {
    final rows = await db.query(
      'visit_tag',
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
    return rows.map((row) => row['tag_id'] as String).toList();
  }

  Future<void> setTagsForVisit(String visitId, List<String> tagIds) async {
    await db.transaction((txn) async {
      await txn.delete(
        'visit_tag',
        where: 'visit_id = ?',
        whereArgs: [visitId],
      );
      final batch = txn.batch();
      for (final tagId in tagIds.toSet()) {
        batch.insert('visit_tag', {'visit_id': visitId, 'tag_id': tagId});
      }
      await batch.commit(noResult: true);
    });
  }

  Future<VisitRecord?> latestVisit() async {
    final rows = await db.query(
      'visit',
      orderBy: 'updated_at DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VisitRecord.fromMap(rows.first);
  }
}
