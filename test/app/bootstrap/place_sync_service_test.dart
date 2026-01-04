import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:world_visit_app/app/bootstrap/place_sync_service.dart';
import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/place_assets/place_assets_loader.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sync inserts places, stats, and meta hash', () async {
    final databaseFactory = databaseFactoryFfi;
    final dbDir = await databaseFactory.getDatabasesPath();
    final dbPath = p.join(dbDir, 'place_sync_test.db');
    await databaseFactory.deleteDatabase(dbPath);

    final appDatabase = AppDatabase(factory: databaseFactoryFfi);
    final loader = _FakeLoader(
      PlaceAssetsData(
        places: const [
          PlaceMasterEntry(
            placeCode: 'JP',
            type: 'country',
            nameJa: '日本',
            nameEn: 'Japan',
            isActive: true,
            sortOrder: 1,
            drawOrder: 200,
            geometryId: 'JP',
          ),
        ],
        aliases: const {
          'JP': ['Nippon'],
        },
        meta: const PlaceMasterMeta(hash: 'hash-1', revision: 'rev-1'),
      ),
    );

    final service = PlaceSyncService(
      openDatabase: () => appDatabase.open(path: dbPath),
      assetsLoader: loader,
    );

    await service.syncIfNeeded();

    final db = await appDatabase.open(path: dbPath);
    final places = await db.query('place');
    expect(places, hasLength(1));
    final aliases = await db.query('place_alias');
    expect(aliases.single['alias_norm'], 'nippon');
    final stats = await db.query('place_stats');
    expect(stats, hasLength(1));
    expect(stats.single['place_code'], 'JP');
    final meta = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['place_master_hash'],
    );
    expect(meta.single['value'], 'hash-1');
    await db.close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('sync stores world data set (>=100 places)', () async {
    final databaseFactory = databaseFactoryFfi;
    final dbDir = await databaseFactory.getDatabasesPath();
    final dbPath = p.join(dbDir, 'place_sync_world.db');
    await databaseFactory.deleteDatabase(dbPath);

    final appDatabase = AppDatabase(factory: databaseFactoryFfi);
    final loader = PlaceAssetsLoader();
    final service = PlaceSyncService(
      openDatabase: () => appDatabase.open(path: dbPath),
      assetsLoader: loader,
    );

    await service.syncIfNeeded();
    await service.syncIfNeeded();

    final db = await appDatabase.open(path: dbPath);
    final places = await db.query('place');
    expect(places.length, greaterThanOrEqualTo(100));
    final meta = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['place_master_hash'],
    );
    expect(meta.single['value'], isNotNull);
    await db.close();
    await databaseFactory.deleteDatabase(dbPath);
  });
}

class _FakeLoader extends PlaceAssetsLoader {
  _FakeLoader(this._data);

  final PlaceAssetsData _data;

  @override
  Future<PlaceAssetsData> load() async => _data;
}
