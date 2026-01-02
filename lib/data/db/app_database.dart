import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

const _schemaVersionKey = 'schema_version';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory})
    : _databaseFactory = factory ?? databaseFactory;

  final DatabaseFactory _databaseFactory;

  Future<Database> open({String? path}) async {
    final resolvedPath = path ?? await _defaultDbPath();
    final db = await _databaseFactory.openDatabase(resolvedPath);
    await _configure(db);
    return db;
  }

  Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
    await db.execute('''
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''');
    await _runMigrations(db);
  }

  Future<void> _runMigrations(Database db) async {
    final appliedVersion = await _readSchemaVersion(db);
    var currentVersion = appliedVersion;

    for (final migration in schemaMigrations) {
      if (migration.version <= currentVersion) {
        continue;
      }

      await db.transaction((txn) async {
        for (final statement in migration.statements) {
          await txn.execute(statement);
        }
        await txn.insert('meta', {
          'key': _schemaVersionKey,
          'value': migration.version.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

      currentVersion = migration.version;
    }
  }

  Future<int> _readSchemaVersion(Database db) async {
    final result = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_schemaVersionKey],
      limit: 1,
    );
    if (result.isEmpty) {
      return 0;
    }
    final rawValue = result.first['value'];
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is String) {
      return int.tryParse(rawValue) ?? 0;
    }
    return 0;
  }

  Future<String> _defaultDbPath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, 'keikoku.db');
  }
}
