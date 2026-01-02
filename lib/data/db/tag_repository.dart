import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:world_visit_app/util/normalize.dart';

class TagRecord {
  const TagRecord({
    required this.tagId,
    required this.name,
    required this.nameNorm,
    required this.createdAt,
    required this.updatedAt,
  });

  final String tagId;
  final String name;
  final String nameNorm;
  final int createdAt;
  final int updatedAt;

  factory TagRecord.fromMap(Map<String, Object?> row) {
    return TagRecord(
      tagId: row['tag_id'] as String,
      name: row['name'] as String,
      nameNorm: row['name_norm'] as String,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'tag_id': tagId,
      'name': name,
      'name_norm': nameNorm,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class TagRepository {
  TagRepository(this.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Database db;
  final Uuid _uuid;

  Future<TagRecord> getOrCreateByName(String name) async {
    final trimmed = name.trim();
    final normalized = normalizeText(trimmed);
    if (normalized.isEmpty) {
      throw ArgumentError('Tag name is empty');
    }
    final existing = await db.query(
      'tag',
      where: 'name_norm = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return TagRecord.fromMap(existing.first);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tagId = _uuid.v4();
    final record = TagRecord(
      tagId: tagId,
      name: trimmed,
      nameNorm: normalized,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await db.insert('tag', record.toMap());
    return record;
  }

  Future<List<TagRecord>> listAll() async {
    final rows = await db.query('tag', orderBy: 'name ASC');
    return rows.map(TagRecord.fromMap).toList();
  }

  Future<List<TagRecord>> getByIds(Iterable<String> tagIds) async {
    if (tagIds.isEmpty) return [];
    final placeholders = List.filled(tagIds.length, '?').join(',');
    final rows = await db.query(
      'tag',
      where: 'tag_id IN ($placeholders)',
      whereArgs: tagIds.toList(),
    );
    return rows.map(TagRecord.fromMap).toList();
  }

  Future<List<TagRecord>> listByVisitId(String visitId) async {
    final rows = await db.rawQuery(
      '''
SELECT t.* FROM tag t
INNER JOIN visit_tag vt ON vt.tag_id = t.tag_id
WHERE vt.visit_id = ?
ORDER BY t.name ASC
''',
      [visitId],
    );
    return rows.map(TagRecord.fromMap).toList();
  }
}
