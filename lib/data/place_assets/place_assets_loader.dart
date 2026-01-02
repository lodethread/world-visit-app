import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

const _kDefaultMasterPath = 'assets/places/place_master.json';
const _kDefaultAliasPath = 'assets/places/place_aliases.json';
const _kDefaultMetaPath = 'assets/places/place_master_meta.json';

@immutable
class PlaceMasterEntry {
  const PlaceMasterEntry({
    required this.placeCode,
    required this.type,
    required this.nameJa,
    required this.nameEn,
    required this.isActive,
    required this.sortOrder,
    required this.drawOrder,
    this.geometryId,
  });

  final String placeCode;
  final String type;
  final String nameJa;
  final String nameEn;
  final bool isActive;
  final int sortOrder;
  final int drawOrder;
  final String? geometryId;
}

@immutable
class PlaceMasterMeta {
  const PlaceMasterMeta({required this.hash, required this.revision});

  final String hash;
  final String revision;
}

@immutable
class PlaceAssetsData {
  const PlaceAssetsData({
    required this.places,
    required this.aliases,
    required this.meta,
  });

  final List<PlaceMasterEntry> places;
  final Map<String, List<String>> aliases;
  final PlaceMasterMeta meta;
}

class PlaceAssetsLoader {
  PlaceAssetsLoader({
    AssetBundle? bundle,
    this.placePath = _kDefaultMasterPath,
    this.aliasPath = _kDefaultAliasPath,
    this.metaPath = _kDefaultMetaPath,
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String placePath;
  final String aliasPath;
  final String metaPath;

  Future<PlaceAssetsData> load() async {
    final placesRaw = await _bundle.loadString(placePath);
    final aliasesRaw = await _bundle.loadString(aliasPath);
    final metaRaw = await _bundle.loadString(metaPath);

    final List<dynamic> placesJson = jsonDecode(placesRaw) as List<dynamic>;
    final Map<String, dynamic> aliasesJson =
        jsonDecode(aliasesRaw) as Map<String, dynamic>;
    final Map<String, dynamic> metaJson =
        jsonDecode(metaRaw) as Map<String, dynamic>;

    final places = <PlaceMasterEntry>[];
    final usedCodes = <String>{};
    for (final entry in placesJson) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Each place entry must be an object');
      }
      final placeCode = entry['place_code']?.toString();
      final type = entry['type']?.toString();
      final nameJa = entry['name_ja']?.toString();
      final nameEn = entry['name_en']?.toString();
      final isActive = entry['is_active'];
      final sortOrder = entry['sort_order'];
      final drawOrder = entry['draw_order'];
      if (placeCode == null || placeCode.isEmpty) {
        throw const FormatException('place_code is required');
      }
      if (usedCodes.contains(placeCode)) {
        throw FormatException('place_code $placeCode is duplicated');
      }
      if (nameJa == null || nameJa.trim().isEmpty) {
        throw FormatException('name_ja is required for $placeCode');
      }
      if (nameEn == null || nameEn.trim().isEmpty) {
        throw FormatException('name_en is required for $placeCode');
      }
      if (type == null || type.isEmpty) {
        throw FormatException('type is required for $placeCode');
      }
      if (isActive is! bool) {
        throw FormatException('is_active must be boolean for $placeCode');
      }
      if (sortOrder is! num) {
        throw FormatException('sort_order must be numeric for $placeCode');
      }
      if (drawOrder is! num) {
        throw FormatException('draw_order must be numeric for $placeCode');
      }
      usedCodes.add(placeCode);
      places.add(
        PlaceMasterEntry(
          placeCode: placeCode,
          type: type,
          nameJa: nameJa,
          nameEn: nameEn,
          isActive: isActive,
          sortOrder: sortOrder.toInt(),
          drawOrder: drawOrder.toInt(),
          geometryId: entry['geometry_id']?.toString(),
        ),
      );
    }

    final aliases = <String, List<String>>{};
    aliasesJson.forEach((key, value) {
      final code = key.toString();
      final entries = <String>{};
      if (value is List) {
        for (final alias in value) {
          final aliasValue = alias?.toString().trim() ?? '';
          if (aliasValue.isEmpty) continue;
          entries.add(aliasValue);
        }
      }
      aliases[code] = entries.toList();
    });

    for (final entry in places) {
      aliases.putIfAbsent(entry.placeCode, () => <String>[]);
    }

    final hash = metaJson['hash']?.toString();
    final revision = metaJson['revision']?.toString();
    if (hash == null || hash.isEmpty) {
      throw const FormatException('meta.hash is required');
    }
    if (revision == null || revision.isEmpty) {
      throw const FormatException('meta.revision is required');
    }

    return PlaceAssetsData(
      places: List.unmodifiable(places),
      aliases: Map.unmodifiable(
        aliases.map(
          (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
        ),
      ),
      meta: PlaceMasterMeta(hash: hash, revision: revision),
    );
  }
}
