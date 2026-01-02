import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/place_repository.dart';
import 'package:world_visit_app/data/place_assets/place_assets_loader.dart';
import 'package:world_visit_app/util/normalize.dart';

const _kMetaHashKey = 'place_master_hash';
const _kMetaRevisionKey = 'place_master_revision';

class PlaceSyncService {
  PlaceSyncService({
    Future<Database> Function()? openDatabase,
    PlaceAssetsLoader? assetsLoader,
  }) : _openDatabase = openDatabase ?? (() => AppDatabase().open()),
       _assetsLoader = assetsLoader ?? PlaceAssetsLoader();

  final Future<Database> Function() _openDatabase;
  final PlaceAssetsLoader _assetsLoader;
  Database? _db;

  Future<void> syncIfNeeded() async {
    final db = _db ??= await _openDatabase();
    final assets = await _assetsLoader.load();
    final currentHash = await _readMeta(db, _kMetaHashKey);
    final repo = PlaceRepository(db);
    final placeCodes = assets.places.map((e) => e.placeCode).toList();

    if (currentHash == assets.meta.hash) {
      await repo.ensurePlaceStatsRows(placeCodes);
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final placeRecords = assets.places
        .map(
          (entry) => PlaceRecord(
            placeCode: entry.placeCode,
            type: entry.type,
            nameJa: entry.nameJa,
            nameEn: entry.nameEn,
            isActive: entry.isActive,
            sortOrder: entry.sortOrder,
            geometryId: entry.geometryId,
            updatedAt: now,
          ),
        )
        .toList();

    await repo.upsertPlaces(placeRecords);
    for (final entry in placeCodes) {
      final aliasList = assets.aliases[entry] ?? const [];
      final aliasRecords = aliasList
          .map(
            (alias) => PlaceAliasRecord(
              placeCode: entry,
              alias: alias,
              aliasNorm: normalizeText(alias),
            ),
          )
          .toList();
      await repo.replaceAliases(entry, aliasRecords);
    }
    await repo.ensurePlaceStatsRows(placeCodes);
    await _writeMeta(db, _kMetaHashKey, assets.meta.hash);
    await _writeMeta(db, _kMetaRevisionKey, assets.meta.revision);
  }

  Future<String?> _readMeta(Database db, String key) async {
    final result = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final dynamic value = result.first['value'];
    if (value == null) return null;
    return value.toString();
  }

  Future<void> _writeMeta(Database db, String key, String value) async {
    await db.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
