import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/features/import_export/model/export_payload.dart';
import 'package:world_visit_app/features/import_export/model/import_issue.dart';
import 'package:world_visit_app/features/import_export/model/import_preview.dart';
import 'package:world_visit_app/util/normalize.dart';

const _jsonFormat = 'explonation';
const _jsonVersion = 1;
const _dateRegex = r'^\d{4}-\d{2}-\d{2}$';
final _datePattern = RegExp(_dateRegex);

enum ImportSourceType { json, csv }

class ImportSession {
  ImportSession._({
    required this.sourceType,
    required this.preview,
    required this.issues,
    required List<_TagUpsert> pendingTags,
    required List<_VisitUpsert> pendingVisits,
  }) : _pendingTags = pendingTags,
       _pendingVisits = pendingVisits;

  final ImportSourceType sourceType;
  final ImportPreview preview;
  final List<ImportIssue> issues;
  final List<_TagUpsert> _pendingTags;
  final List<_VisitUpsert> _pendingVisits;

  bool get hasErrors =>
      issues.any((issue) => issue.severity == ImportIssueSeverity.error);
}

class ImportResult {
  const ImportResult({
    required this.applied,
    required this.preview,
    required this.issues,
  });

  final bool applied;
  final ImportPreview preview;
  final List<ImportIssue> issues;
}

class ImportExportService {
  ImportExportService({Database? database})
    : _providedDatabase = database,
      _ownsDatabase = database == null;

  final Database? _providedDatabase;
  final bool _ownsDatabase;
  Database? _openedDb;
  final _uuid = const Uuid();

  Future<void> dispose() async {
    if (_ownsDatabase) {
      await _openedDb?.close();
    }
  }

  Future<File> exportJson({Directory? directory}) async {
    final payload = await _buildExportPayload();
    final dir = directory ?? await getApplicationDocumentsDirectory();
    final file = File(
      p.join(dir.path, 'explonation_export_${_fileTimestamp()}.json'),
    );
    await file.writeAsString(jsonEncode(payload.toJson()));
    return file;
  }

  Future<File> exportCsv({Directory? directory}) async {
    final db = await _db();
    final tagRows = await db.query('tag');
    final tagsById = {
      for (final row in tagRows) row['tag_id'] as String: row['name'] as String,
    };
    final visitRows = await db.query('visit');
    final visitTagRows = await db.query('visit_tag');
    final visitTags = <String, List<String>>{};
    for (final row in visitTagRows) {
      final visitId = row['visit_id'] as String;
      final tagId = row['tag_id'] as String;
      visitTags.putIfAbsent(visitId, () => []).add(tagId);
    }
    final rows = <List<dynamic>>[
      [
        'visit_id',
        'place_code',
        'title',
        'start_date',
        'end_date',
        'level',
        'tags',
        'note',
        'created_at',
        'updated_at',
      ],
    ];
    for (final visit in visitRows) {
      final visitId = visit['visit_id'] as String;
      final tagNames = (visitTags[visitId] ?? const [])
          .map((tagId) => tagsById[tagId])
          .whereType<String>()
          .where((name) => !name.contains(';'))
          .toList();
      rows.add([
        visitId,
        visit['place_code'],
        visit['title'],
        visit['start_date'],
        visit['end_date'],
        visit['level'],
        tagNames.join(';'),
        visit['note'],
        visit['created_at'],
        visit['updated_at'],
      ]);
    }
    final csv = const ListToCsvConverter().convert(rows);
    final dir = directory ?? await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'visits_${_fileTimestamp()}.csv'));
    await file.writeAsString(csv);
    return file;
  }

  Future<ImportSession> prepareJsonImport(String content) async {
    final issues = <ImportIssue>[];
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (error) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'INVALID_JSON',
          message: 'JSONの解析に失敗しました: $error',
          location: '/',
        ),
      );
      return _emptyPlan(ImportSourceType.json, issues);
    }

    if (decoded is! Map<String, dynamic>) {
      issues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'INVALID_ROOT',
          message: 'JSONのトップレベルはオブジェクトである必要があります。',
          location: '/',
        ),
      );
      return _emptyPlan(ImportSourceType.json, issues);
    }

    final format = decoded['format']?.toString();
    final version = decoded['version'];
    if (format != _jsonFormat || version != _jsonVersion) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'VERSION_MISMATCH',
          message: 'format=$_jsonFormat / version=$_jsonVersion のファイルのみ取り込めます。',
          location: '/',
        ),
      );
      return _emptyPlan(ImportSourceType.json, issues);
    }

    final tags = (decoded['tags'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final visits = (decoded['visits'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final db = await _db();
    final existing = await _loadExistingData(db);
    final tagResolution = _resolveJsonTags(tags, existing, issues);
    final visitPlan = _buildVisitPlansFromJson(
      visits,
      existing,
      tagResolution,
      issues,
    );

    final preview = _buildPreview(
      visitsTotal: visits.length,
      pendingVisits: visitPlan,
      pendingTags: tagResolution.pendingTags,
      issues: issues,
    );

    return ImportSession._(
      sourceType: ImportSourceType.json,
      preview: preview,
      issues: issues,
      pendingTags: tagResolution.pendingTags,
      pendingVisits: visitPlan,
    );
  }

  Future<ImportSession> prepareCsvImport(String content) async {
    final issues = <ImportIssue>[];
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(content);
    if (rows.isEmpty) {
      issues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'EMPTY_FILE',
          message: 'CSVに行がありません。',
          location: 'row 1',
        ),
      );
      return _emptyPlan(ImportSourceType.csv, issues);
    }

    final header = rows.first.map((cell) => cell.toString().trim()).toList();
    final requiredColumns = [
      'visit_id',
      'place_code',
      'title',
      'start_date',
      'end_date',
      'level',
      'tags',
      'note',
      'created_at',
      'updated_at',
    ];
    for (final column in requiredColumns) {
      if (!header.contains(column)) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.error,
            code: 'MISSING_COLUMN',
            message: 'CSVに列 $column が存在しません。',
            location: 'header',
          ),
        );
      }
    }
    if (issues.isNotEmpty) {
      return _emptyPlan(ImportSourceType.csv, issues);
    }

    final db = await _db();
    final existing = await _loadExistingData(db);
    final tagResolution = _TagResolution(existing: existing);

    final pendingVisits = <_VisitUpsert>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final rawRow = rows[rowIndex];
      final map = <String, String>{};
      for (
        var colIndex = 0;
        colIndex < header.length && colIndex < rawRow.length;
        colIndex++
      ) {
        map[header[colIndex]] = rawRow[colIndex]?.toString() ?? '';
      }
      final visit = _visitFromCsvRow(
        rowIndex,
        map,
        existing,
        tagResolution,
        issues,
      );
      if (visit != null) {
        pendingVisits.add(visit);
      }
    }

    final preview = _buildPreview(
      visitsTotal: rows.length - 1,
      pendingVisits: pendingVisits,
      pendingTags: tagResolution.pendingTags,
      issues: issues,
    );

    return ImportSession._(
      sourceType: ImportSourceType.csv,
      preview: preview,
      issues: issues,
      pendingTags: tagResolution.pendingTags,
      pendingVisits: pendingVisits,
    );
  }

  Future<ImportResult> executeImportPlan(
    ImportSession plan, {
    bool strictMode = false,
  }) async {
    if (strictMode && plan.hasErrors) {
      return ImportResult(
        applied: false,
        preview: plan.preview,
        issues: plan.issues,
      );
    }
    final db = await _db();
    await db.transaction((txn) async {
      for (final tag in plan._pendingTags) {
        final data = {
          'tag_id': tag.tagId,
          'name': tag.name,
          'name_norm': tag.nameNorm,
          'created_at': tag.createdAt,
          'updated_at': tag.updatedAt,
        };
        if (tag.isInsert) {
          await txn.insert(
            'tag',
            data,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await txn.update(
            'tag',
            data,
            where: 'tag_id = ?',
            whereArgs: [tag.tagId],
          );
        }
      }
      for (final visit in plan._pendingVisits) {
        if (visit.isInsert) {
          await txn.insert(
            'visit',
            visit.values,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await txn.update(
            'visit',
            visit.values,
            where: 'visit_id = ?',
            whereArgs: [visit.visitId],
          );
        }
        await txn.delete(
          'visit_tag',
          where: 'visit_id = ?',
          whereArgs: [visit.visitId],
        );
        for (final tagId in visit.tagIds) {
          await txn.insert('visit_tag', {
            'visit_id': visit.visitId,
            'tag_id': tagId,
          });
        }
      }
    });
    return ImportResult(
      applied: true,
      preview: plan.preview,
      issues: plan.issues,
    );
  }

  Future<ExportPayload> _buildExportPayload() async {
    final db = await _db();
    final tagRows = await db.query('tag', orderBy: 'created_at ASC');
    final visitRows = await db.query('visit', orderBy: 'updated_at DESC');
    final visitTagRows = await db.query('visit_tag');
    final visitTags = <String, List<String>>{};
    for (final row in visitTagRows) {
      final visitId = row['visit_id'] as String;
      final tagId = row['tag_id'] as String;
      visitTags.putIfAbsent(visitId, () => []).add(tagId);
    }
    return ExportPayload(
      format: _jsonFormat,
      version: _jsonVersion,
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      tags: tagRows
          .map(
            (row) => ExportTag(
              tagId: row['tag_id'] as String,
              name: row['name'] as String,
              createdAt: row['created_at'] as int,
              updatedAt: row['updated_at'] as int,
            ),
          )
          .toList(),
      visits: visitRows
          .map(
            (row) => ExportVisit(
              visitId: row['visit_id'] as String,
              placeCode: row['place_code'] as String,
              title: row['title'] as String,
              level: row['level'] as int,
              startDate: row['start_date'] as String?,
              endDate: row['end_date'] as String?,
              note: row['note'] as String?,
              createdAt: row['created_at'] as int,
              updatedAt: row['updated_at'] as int,
              tagIds: List<String>.from(visitTags[row['visit_id']] ?? const []),
            ),
          )
          .toList(),
    );
  }

  Future<Database> _db() async {
    if (_providedDatabase != null) {
      return _providedDatabase;
    }
    _openedDb ??= await AppDatabase().open();
    return _openedDb!;
  }

  ImportSession _emptyPlan(ImportSourceType type, List<ImportIssue> issues) {
    final preview = _buildPreview(
      visitsTotal: 0,
      pendingVisits: const [],
      pendingTags: const [],
      issues: issues,
    );
    return ImportSession._(
      sourceType: type,
      preview: preview,
      issues: issues,
      pendingTags: const [],
      pendingVisits: const [],
    );
  }

  ImportPreview _buildPreview({
    required int visitsTotal,
    required List<_VisitUpsert> pendingVisits,
    required List<_TagUpsert> pendingTags,
    required List<ImportIssue> issues,
  }) {
    final inserts = pendingVisits.where((v) => v.isInsert).length;
    final updates = pendingVisits.length - inserts;
    final tagsCreate = pendingTags.where((t) => t.isInsert).length;
    final errorCount = issues
        .where((i) => i.severity == ImportIssueSeverity.error)
        .length;
    final warningCount = issues
        .where((i) => i.severity == ImportIssueSeverity.warning)
        .length;
    return ImportPreview(
      visitsTotal: visitsTotal,
      valid: pendingVisits.length,
      skipped: visitsTotal - pendingVisits.length,
      inserts: inserts,
      updates: updates,
      tagsToCreate: tagsCreate,
      errorCount: errorCount,
      warningCount: warningCount,
    );
  }

  Future<_ExistingData> _loadExistingData(Database db) async {
    final placeRows = await db.query('place', columns: ['place_code']);
    final tagRows = await db.query('tag');
    final visitRows = await db.query('visit');
    final placeCodes = placeRows
        .map((row) => row['place_code'] as String)
        .toSet();
    final tagsById = <String, Map<String, Object?>>{};
    final tagsByNorm = <String, Map<String, Object?>>{};
    for (final row in tagRows) {
      final tagId = row['tag_id'] as String;
      tagsById[tagId] = row;
      tagsByNorm[row['name_norm'] as String] = row;
    }
    final visitsById = {
      for (final row in visitRows) row['visit_id'] as String: row,
    };
    return _ExistingData(
      placeCodes: placeCodes,
      tagsById: tagsById,
      tagsByNorm: tagsByNorm,
      visitsById: visitsById,
    );
  }

  _TagResolution _resolveJsonTags(
    List<Map<String, dynamic>> tags,
    _ExistingData existing,
    List<ImportIssue> issues,
  ) {
    final resolution = _TagResolution(existing: existing);
    for (var index = 0; index < tags.length; index++) {
      final tag = tags[index];
      final name = tag['name']?.toString() ?? '';
      final nameNorm = normalizeText(name);
      if (nameNorm.isEmpty) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            code: 'TAG_NAME_EMPTY',
            message: 'タグ名が空のためスキップしました。',
            location: '/tags/$index',
          ),
        );
        continue;
      }
      final tagId = tag['tag_id']?.toString();
      final createdAt =
          _asInt(tag['created_at']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAt = _asInt(tag['updated_at']) ?? createdAt;
      resolution.addTag(
        desiredId: tagId,
        name: name,
        nameNorm: nameNorm,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }
    return resolution;
  }

  List<_VisitUpsert> _buildVisitPlansFromJson(
    List<Map<String, dynamic>> visits,
    _ExistingData existing,
    _TagResolution resolution,
    List<ImportIssue> issues,
  ) {
    final pending = <_VisitUpsert>[];
    for (var index = 0; index < visits.length; index++) {
      final location = '/visits/$index';
      final visit = visits[index];
      final visitId = visit['visit_id']?.toString();
      if (visitId == null || visitId.isEmpty) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.error,
            code: 'VISIT_ID_MISSING',
            message: 'visit_id が必須です。',
            location: location,
          ),
        );
        continue;
      }
      final validation = _validateVisitData(
        location: location,
        visitId: visitId,
        placeCode: visit['place_code']?.toString(),
        title: visit['title']?.toString(),
        levelValue: visit['level'],
        startDate: visit['start_date']?.toString(),
        endDate: visit['end_date']?.toString(),
        existing: existing,
        issues: issues,
      );
      if (validation == null) {
        continue;
      }
      final timestamps = _resolveTimestamps(
        visit,
        existingVisit: existing.visitsById[visitId],
      );
      final tagIds = <String>[];
      final rawTagIds = visit['tag_ids'] as List<dynamic>?;
      if (rawTagIds != null) {
        for (final dynamicId in rawTagIds) {
          final resolved = resolution.resolveTagId(dynamicId?.toString());
          if (resolved != null) {
            tagIds.add(resolved);
          } else {
            issues.add(
              ImportIssue(
                severity: ImportIssueSeverity.warning,
                code: 'UNKNOWN_TAG_ID',
                message: 'tag_id ${dynamicId ?? 'null'} は存在しません。',
                location: location,
                context: {'visit_id': visitId},
              ),
            );
          }
        }
      }
      final upsert = _VisitUpsert(
        visitId: visitId,
        isInsert: !existing.visitsById.containsKey(visitId),
        values: {
          'visit_id': visitId,
          'place_code': validation.placeCode,
          'title': validation.title,
          'start_date': validation.startDate,
          'end_date': validation.endDate,
          'level': validation.level,
          'note': visit['note']?.toString(),
          'created_at': timestamps.createdAt,
          'updated_at': timestamps.updatedAt,
        },
        tagIds: tagIds.toSet().toList(),
      );
      pending.add(upsert);
    }
    return pending;
  }

  _VisitUpsert? _visitFromCsvRow(
    int rowIndex,
    Map<String, String> row,
    _ExistingData existing,
    _TagResolution resolution,
    List<ImportIssue> issues,
  ) {
    final idValue = row['visit_id'];
    final visitId = (idValue == null || idValue.isEmpty) ? _uuid.v4() : idValue;
    final location = 'row ${rowIndex + 1}';
    final validation = _validateVisitData(
      location: location,
      visitId: visitId,
      placeCode: row['place_code'],
      title: row['title'],
      levelValue: row['level'],
      startDate: row['start_date'],
      endDate: row['end_date'],
      existing: existing,
      issues: issues,
    );
    if (validation == null) {
      return null;
    }
    final createdAt =
        int.tryParse(row['created_at'] ?? '') ??
        existing.visitsById[visitId]?['created_at'] as int? ??
        DateTime.now().millisecondsSinceEpoch;
    final updatedAt =
        int.tryParse(row['updated_at'] ?? '') ??
        DateTime.now().millisecondsSinceEpoch;

    final tagCell = row['tags'] ?? '';
    final tagNames = tagCell
        .split(';')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final tagIds = <String>[];
    for (final name in tagNames) {
      final nameNorm = normalizeText(name);
      if (nameNorm.isEmpty) {
        continue;
      }
      final existingTag = existing.tagsByNorm[nameNorm];
      if (existingTag != null) {
        tagIds.add(existingTag['tag_id'] as String);
        continue;
      }
      final resolved = resolution.addTag(
        desiredId: null,
        name: name,
        nameNorm: nameNorm,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      if (resolved != null) {
        tagIds.add(resolved.tagId);
      }
    }

    return _VisitUpsert(
      visitId: visitId,
      isInsert: !existing.visitsById.containsKey(visitId),
      values: {
        'visit_id': visitId,
        'place_code': validation.placeCode,
        'title': validation.title,
        'start_date': validation.startDate,
        'end_date': validation.endDate,
        'level': validation.level,
        'note': row['note'],
        'created_at': createdAt,
        'updated_at': updatedAt,
      },
      tagIds: tagIds.toSet().toList(),
    );
  }

  _VisitValidation? _validateVisitData({
    required String location,
    required String visitId,
    String? placeCode,
    String? title,
    Object? levelValue,
    String? startDate,
    String? endDate,
    required _ExistingData existing,
    required List<ImportIssue> issues,
  }) {
    final normalizedPlace = placeCode?.trim();
    if (normalizedPlace == null || normalizedPlace.isEmpty) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'PLACE_CODE_MISSING',
          message: 'place_code が必須です。',
          location: location,
          context: {'visit_id': visitId},
        ),
      );
      return null;
    }
    if (!existing.placeCodes.contains(normalizedPlace)) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'UNKNOWN_PLACE_CODE',
          message: 'place_code $normalizedPlace は登録されていません。',
          location: location,
          context: {'visit_id': visitId, 'place_code': normalizedPlace},
        ),
      );
      return null;
    }
    final trimmedTitle = title?.trim() ?? '';
    if (trimmedTitle.isEmpty) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'TITLE_EMPTY',
          message: 'title は必須です。',
          location: location,
          context: {'visit_id': visitId},
        ),
      );
      return null;
    }
    final level = _asInt(levelValue);
    if (level == null || level < 1 || level > 5) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'LEVEL_INVALID',
          message: 'level は1~5の整数です。',
          location: location,
          context: {'visit_id': visitId, 'raw_level': levelValue},
        ),
      );
      return null;
    }
    final normalizedStart = _normalizeDate(startDate);
    final normalizedEnd = _normalizeDate(endDate);
    if (normalizedStart == null && startDate != null && startDate.isNotEmpty) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'START_DATE_INVALID',
          message: 'start_date の形式が不正です。',
          location: location,
          context: {'visit_id': visitId, 'start_date': startDate},
        ),
      );
      return null;
    }
    if (normalizedEnd == null && endDate != null && endDate.isNotEmpty) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'END_DATE_INVALID',
          message: 'end_date の形式が不正です。',
          location: location,
          context: {'visit_id': visitId, 'end_date': endDate},
        ),
      );
      return null;
    }
    if (normalizedStart != null &&
        normalizedEnd != null &&
        normalizedStart.compareTo(normalizedEnd) > 0) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.error,
          code: 'DATE_RANGE_INVALID',
          message: 'start_date は end_date 以下である必要があります。',
          location: location,
          context: {'visit_id': visitId},
        ),
      );
      return null;
    }
    return _VisitValidation(
      placeCode: normalizedPlace,
      title: trimmedTitle,
      level: level,
      startDate: normalizedStart,
      endDate: normalizedEnd,
    );
  }

  _TimestampPair _resolveTimestamps(
    Map<String, dynamic> payload, {
    Map<String, Object?>? existingVisit,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final created =
        _asInt(payload['created_at']) ??
        existingVisit?['created_at'] as int? ??
        now;
    final updated = _asInt(payload['updated_at']) ?? now;
    return _TimestampPair(createdAt: created, updatedAt: updated);
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _normalizeDate(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return _datePattern.hasMatch(trimmed) ? trimmed : null;
  }

  String _fileTimestamp() {
    final now = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

class _VisitUpsert {
  _VisitUpsert({
    required this.visitId,
    required this.isInsert,
    required this.values,
    required this.tagIds,
  });

  final String visitId;
  final bool isInsert;
  final Map<String, Object?> values;
  final List<String> tagIds;
}

class _TagUpsert {
  _TagUpsert({
    required this.tagId,
    required this.name,
    required this.nameNorm,
    required this.createdAt,
    required this.updatedAt,
    required this.isInsert,
  });

  final String tagId;
  final String name;
  final String nameNorm;
  final int createdAt;
  final int updatedAt;
  final bool isInsert;
}

class _ExistingData {
  _ExistingData({
    required this.placeCodes,
    required this.tagsById,
    required this.tagsByNorm,
    required this.visitsById,
  });

  final Set<String> placeCodes;
  final Map<String, Map<String, Object?>> tagsById;
  final Map<String, Map<String, Object?>> tagsByNorm;
  final Map<String, Map<String, Object?>> visitsById;
}

class _VisitValidation {
  _VisitValidation({
    required this.placeCode,
    required this.title,
    required this.level,
    required this.startDate,
    required this.endDate,
  });

  final String placeCode;
  final String title;
  final int level;
  final String? startDate;
  final String? endDate;
}

class _TimestampPair {
  const _TimestampPair({required this.createdAt, required this.updatedAt});
  final int createdAt;
  final int updatedAt;
}

class _TagResolution {
  _TagResolution({required this.existing}) : _uuid = const Uuid();

  final _ExistingData existing;
  final List<_TagUpsert> pendingTags = [];
  final Map<String, String> _incomingToActual = {};
  final Uuid _uuid;

  _TagUpsert? addTag({
    String? desiredId,
    required String name,
    required String nameNorm,
    required int createdAt,
    required int updatedAt,
  }) {
    if (nameNorm.isEmpty) {
      return null;
    }
    String? tagId = desiredId?.isNotEmpty == true ? desiredId : null;
    Map<String, Object?>? existingRow;
    if (tagId != null) {
      _incomingToActual[tagId] = tagId;
      existingRow = existing.tagsById[tagId];
    } else {
      existingRow = existing.tagsByNorm[nameNorm];
      tagId = existingRow?['tag_id'] as String?;
    }
    final isInsert = tagId == null || existingRow == null;
    tagId ??= _uuid.v4();
    final upsert = _TagUpsert(
      tagId: tagId,
      name: name,
      nameNorm: nameNorm,
      createdAt: existing.tagsById[tagId]?['created_at'] as int? ?? createdAt,
      updatedAt: updatedAt,
      isInsert: isInsert,
    );
    pendingTags
      ..removeWhere((element) => element.tagId == tagId)
      ..add(upsert);
    final entry =
        existing.tagsById[tagId] ?? <String, Object?>{'tag_id': tagId};
    entry['name_norm'] = nameNorm;
    entry['created_at'] ??= upsert.createdAt;
    existing.tagsById[tagId] = entry;
    existing.tagsByNorm[nameNorm] = {'tag_id': tagId};
    return upsert;
  }

  String? resolveTagId(String? incomingId) {
    if (incomingId == null || incomingId.isEmpty) {
      return null;
    }
    if (_incomingToActual.containsKey(incomingId)) {
      return _incomingToActual[incomingId];
    }
    if (existing.tagsById.containsKey(incomingId)) {
      return incomingId;
    }
    return null;
  }
}
