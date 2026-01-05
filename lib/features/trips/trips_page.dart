import 'package:flutter/material.dart';

import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/user_setting_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/tag/ui/tag_picker_sheet.dart';
import 'package:world_visit_app/features/visit/ui/visit_editor_page.dart';
import 'package:world_visit_app/features/trips/trip_sort.dart';
import 'package:world_visit_app/util/normalize.dart';

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  static const _kTripsSortSettingKey = 'trips_sort';
  final TextEditingController _searchController = TextEditingController();
  List<_TripView> _trips = [];
  List<_TripView> _filtered = [];
  Database? _db;
  late VisitRepository _visitRepository;
  late TagRepository _tagRepository;
  UserSettingRepository? _userSettingRepository;
  bool _loading = true;
  final Set<int> _levelFilters = {};
  final Set<String> _tagFilters = {};
  TripSortOption _sortOption = TripSortOption.recent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase().open();
    _db = db;
    _visitRepository = VisitRepository(db);
    _tagRepository = TagRepository(db);
    _userSettingRepository ??= UserSettingRepository(db);

    final savedSort = await _userSettingRepository!.getValue(
      _kTripsSortSettingKey,
    );
    var sortPreference = tripSortOptionFromStorage(savedSort) ?? _sortOption;

    final placeRows = await db.query('place');
    final aliasRows = await db.query('place_alias');
    final visitRows = await db.query('visit');
    final tagRows = await db.query('tag');
    final visitTagRows = await db.query('visit_tag');
    final statsRows = await db.query('place_stats');

    final statsByPlace = {
      for (final row in statsRows)
        row['place_code'] as String: _PlaceStats(
          maxLevel: (row['max_level'] as int?) ?? 0,
          visitCount: (row['visit_count'] as int?) ?? 0,
        ),
    };

    final places = <String, _PlaceInfo>{};
    for (final row in placeRows) {
      final code = row['place_code'] as String;
      final stats = statsByPlace[code];
      places[code] = _PlaceInfo(
        code: code,
        nameJa: row['name_ja'] as String,
        nameEn: row['name_en'] as String,
        maxLevel: stats?.maxLevel ?? 0,
        visitCount: stats?.visitCount ?? 0,
      );
    }
    final placeTokens = <String, Set<String>>{};
    for (final entry in places.entries) {
      placeTokens[entry.key] = {
        normalizeText(entry.value.nameJa),
        normalizeText(entry.value.nameEn),
      }..removeWhere((value) => value.isEmpty);
    }
    for (final row in aliasRows) {
      final code = row['place_code'] as String;
      placeTokens.putIfAbsent(code, () => <String>{});
      placeTokens[code]!.add(normalizeText(row['alias'] as String));
      placeTokens[code]!.removeWhere((element) => element.isEmpty);
    }

    final tags = {
      for (final row in tagRows)
        row['tag_id'] as String: TagRecord.fromMap(row),
    };

    final visitTags = <String, List<TagRecord>>{};
    for (final row in visitTagRows) {
      final visitId = row['visit_id'] as String;
      final tagId = row['tag_id'] as String;
      final tag = tags[tagId];
      if (tag == null) continue;
      visitTags.putIfAbsent(visitId, () => []).add(tag);
    }

    final trips = <_TripView>[];
    for (final row in visitRows) {
      final visit = VisitRecord.fromMap(row);
      final place = places[visit.placeCode];
      final view = _TripView(
        visit: visit,
        place: place,
        tags: visitTags[visit.visitId] ?? const [],
        searchTokens: {
          normalizeText(visit.title),
          if (place != null) normalizeText(place.nameJa),
          if (place != null) normalizeText(place.nameEn),
          ...?placeTokens[visit.placeCode],
          ...((visitTags[visit.visitId] ?? const []).map(
            (tag) => normalizeText(tag.name),
          )),
        }..removeWhere((token) => token.isEmpty),
      );
      trips.add(view);
    }

    final sortedTrips = _sortedCopy(trips, sortPreference);
    final filteredTrips = _filterTrips(sortedTrips);

    setState(() {
      _sortOption = sortPreference;
      _trips = sortedTrips;
      _filtered = filteredTrips;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _db?.close();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      _filtered = _filterTrips(_trips);
    });
  }

  List<_TripView> _filterTrips(List<_TripView> source) {
    final query = normalizeText(_searchController.text);
    return source.where((trip) {
      if (query.isNotEmpty && !trip.matchesQuery(query)) {
        return false;
      }
      if (_levelFilters.isNotEmpty &&
          !_levelFilters.contains(trip.visit.level)) {
        return false;
      }
      if (_tagFilters.isNotEmpty) {
        final visitTagIds = trip.tags.map((t) => t.tagId).toSet();
        if (!_tagFilters.every(visitTagIds.contains)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<_TripView> _sortedCopy(List<_TripView> source, TripSortOption option) {
    final copy = List<_TripView>.from(source);
    copy.sort((a, b) => compareTrips(a, b, option));
    return copy;
  }

  Future<void> _openEditor({
    _TripView? visit,
    String? initialPlaceCode,
    List<TagRecord>? tags,
    String? initialTitle,
    int? initialLevel,
    String? initialNote,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditorPage(
          initialVisit: visit?.visit,
          initialPlaceCode: initialPlaceCode,
          initialTags: tags ?? visit?.tags,
          initialTitle: visit == null ? initialTitle : null,
          initialLevel: visit == null ? initialLevel : null,
          initialNote: visit == null ? initialNote : null,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      setState(() => _loading = true);
      await _load();
      _applyFilters();
    }
  }

  Future<void> _duplicateLatest() async {
    final latest = await _visitRepository.latestVisit();
    if (latest == null) {
      if (!mounted) return;
      _showMessage('複製できるVisitがありません');
      return;
    }
    final tags = await _tagRepository.listByVisitId(latest.visitId);
    await _openEditor(
      initialPlaceCode: latest.placeCode,
      tags: tags,
      initialTitle: latest.title,
      initialLevel: latest.level,
      initialNote: latest.note,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeSortOption(TripSortOption option) async {
    if (_sortOption == option) {
      return;
    }
    setState(() {
      _sortOption = option;
      _trips = _sortedCopy(_trips, option);
      _filtered = _filterTrips(_trips);
    });
    final repo = _userSettingRepository;
    if (repo != null) {
      await repo.setValue(_kTripsSortSettingKey, option.storageValue);
    }
  }

  Future<void> _pickFilterTags() async {
    final initialSelection = await _tagRepository.getByIds(_tagFilters);
    if (!mounted) return;
    final selectedTags = await TagPickerSheet.show(
      context,
      repository: _tagRepository,
      initialSelection: initialSelection,
    );
    if (!mounted) return;
    if (selectedTags != null) {
      _tagFilters
        ..clear()
        ..addAll(selectedTags.map((tag) => tag.tagId));
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _openEditor(),
            icon: const Icon(Icons.add),
            tooltip: '新規追加',
          ),
          IconButton(
            onPressed: _loading ? null : _duplicateLatest,
            icon: const Icon(Icons.copy),
            tooltip: '直前Visit複製',
          ),
          PopupMenuButton<TripSortOption>(
            tooltip: '並び替え',
            enabled: !_loading,
            initialValue: _sortOption,
            icon: const Icon(Icons.sort),
            onSelected: (value) => _changeSortOption(value),
            itemBuilder: (context) {
              return TripSortOption.values
                  .map(
                    (option) =>
                        PopupMenuItem(value: option, child: Text(option.label)),
                  )
                  .toList();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'タイトル / Place / タグを検索',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => _applyFilters(),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (var level = 1; level <= 5; level++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text('Lv.$level'),
                            selected: _levelFilters.contains(level),
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  _levelFilters.add(level);
                                } else {
                                  _levelFilters.remove(level);
                                }
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(
                          _tagFilters.isEmpty
                              ? 'タグ未選択'
                              : 'タグ ${_tagFilters.length}件',
                        ),
                        selected: _tagFilters.isNotEmpty,
                        onSelected: (_) => _pickFilterTags(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(child: Text('Visitがありません'))
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (context, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final trip = _filtered[index];
                            return ListTile(
                              title: Text(trip.visit.title),
                              subtitle: Text(
                                trip.placeLabel ?? trip.visit.placeCode,
                              ),
                              trailing: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Lv.${trip.visit.level}'),
                                  if (trip.visit.startDate != null)
                                    Text(
                                      trip.visit.endDate == null
                                          ? trip.visit.startDate!
                                          : '${trip.visit.startDate} - ${trip.visit.endDate}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                              onTap: () => _openEditor(visit: trip),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _TripView implements TripSortable {
  _TripView({
    required this.visit,
    required this.place,
    required this.tags,
    required this.searchTokens,
  });

  @override
  final VisitRecord visit;
  final _PlaceInfo? place;
  final List<TagRecord> tags;
  final Set<String> searchTokens;

  String? get placeLabel {
    if (place == null) return null;
    return place!.nameJa;
  }

  @override
  String? get placeNameJa => place?.nameJa;

  @override
  String? get placeNameEn => place?.nameEn;

  @override
  int get placeMaxLevel => place?.maxLevel ?? 0;

  @override
  int get placeVisitCount => place?.visitCount ?? 0;

  bool matchesQuery(String query) {
    if (searchTokens.isEmpty) {
      return normalizeText(visit.title).contains(query);
    }
    return searchTokens.any((token) => token.contains(query));
  }
}

class _PlaceStats {
  const _PlaceStats({required this.maxLevel, required this.visitCount});

  final int maxLevel;
  final int visitCount;
}

class _PlaceInfo {
  _PlaceInfo({
    required this.code,
    required this.nameJa,
    required this.nameEn,
    required this.maxLevel,
    required this.visitCount,
  });

  final String code;
  final String nameJa;
  final String nameEn;
  final int maxLevel;
  final int visitCount;
}
