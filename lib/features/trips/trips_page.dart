import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/user_setting_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/tag/ui/tag_picker_sheet.dart';
import 'package:world_visit_app/features/trips/data/trip_list_loader.dart';
import 'package:world_visit_app/features/visit/ui/visit_editor_page.dart';
import 'package:world_visit_app/features/trips/trip_sort.dart';
import 'package:world_visit_app/util/normalize.dart';
import 'package:world_visit_app/app/ads/widgets/adaptive_banner_ad_widget.dart';

// #region agent log
void _debugLogTrips(
  String location,
  String message,
  Map<String, dynamic> data,
  String hypothesisId,
) {
  final entry = jsonEncode({
    'location': location,
    'message': message,
    'data': data,
    'hypothesisId': hypothesisId,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'sessionId': 'debug-session',
  });
  debugPrint('[DEBUG] $entry');
}
// #endregion

class TripsPage extends StatefulWidget {
  const TripsPage({super.key, this.openDatabase});

  final Future<Database> Function()? openDatabase;

  @override
  State<TripsPage> createState() => TripsPageState();
}

class TripsPageState extends State<TripsPage> {
  static const _kTripsSortSettingKey = 'trips_sort';
  final TextEditingController _searchController = TextEditingController();
  List<_TripView> _trips = [];
  List<_TripView> _filtered = [];
  Database? _db;
  Future<Database> Function()? _openDatabase;
  late VisitRepository _visitRepository;
  late TagRepository _tagRepository;
  UserSettingRepository? _userSettingRepository;
  bool _loading = true;
  final Set<int> _levelFilters = {};
  final Set<String> _tagFilters = {};
  TripSortOption _sortOption = TripSortOption.recent;

  // Stats for summary card
  int _totalScore = 0;
  List<_TopVisitedPlace> _topVisitedPlaces = [];

  @override
  void initState() {
    super.initState();
    _openDatabase = widget.openDatabase ?? () => AppDatabase().open();
    _load();
  }

  /// Refresh the trips list. Called when switching to the Trips tab.
  Future<void> refresh() async {
    setState(() => _loading = true);
    await _load();
    _applyFilters();
  }

  Future<void> _load() async {
    _db ??= await _openDatabase!.call();
    final db = _db!;
    _visitRepository = VisitRepository(db);
    _tagRepository = TagRepository(db);
    _userSettingRepository ??= UserSettingRepository(db);

    final savedSort = await _userSettingRepository!.getValue(
      _kTripsSortSettingKey,
    );
    var sortPreference = tripSortOptionFromStorage(savedSort) ?? _sortOption;

    final loader = TripListLoader(db);
    final source = await loader.load();
    final trips = source
        .map((item) => _TripView.fromItem(item))
        .toList(growable: false);

    // Calculate stats
    final statsRows = await db.query('place_stats');
    int totalScore = 0;
    for (final row in statsRows) {
      final level = (row['max_level'] as int?) ?? 0;
      totalScore += level;
    }

    // Get top visited places by visit_count
    final topPlacesRows = await db.rawQuery('''
      SELECT ps.place_code, ps.visit_count, p.name_ja, p.name_en
      FROM place_stats ps
      JOIN place p ON ps.place_code = p.place_code
      WHERE ps.visit_count > 0
      ORDER BY ps.visit_count DESC
      LIMIT 10
    ''');

    final topPlaces = <_TopVisitedPlace>[];
    if (topPlacesRows.isNotEmpty) {
      final maxCount = topPlacesRows.first['visit_count'] as int;
      for (final row in topPlacesRows) {
        final count = row['visit_count'] as int;
        if (count == maxCount) {
          topPlaces.add(
            _TopVisitedPlace(
              placeCode: row['place_code'] as String,
              visitCount: count,
              nameJa: row['name_ja'] as String?,
              nameEn: row['name_en'] as String?,
            ),
          );
        } else {
          break;
        }
      }
    }
    // Shuffle to pick random one if tied
    topPlaces.shuffle();

    final sortedTrips = _sortedCopy(trips, sortPreference);
    final filteredTrips = _filterTrips(sortedTrips);

    setState(() {
      _sortOption = sortPreference;
      _trips = sortedTrips;
      _filtered = filteredTrips;
      _totalScore = totalScore;
      _topVisitedPlaces = topPlaces;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Note: Do NOT close DB here - it's shared across the app
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
    // #region agent log
    _debugLogTrips('trips_page.dart:_openEditor', 'Opening editor', {
      'hasVisit': visit != null,
      'initialPlaceCode': initialPlaceCode,
      'loading': _loading,
    }, 'E');
    // #endregion
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
    // #region agent log
    _debugLogTrips('trips_page.dart:_openEditor:result', 'Editor returned', {
      'result': result,
      'mounted': mounted,
    }, 'E');
    // #endregion
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

  Widget _buildStatsCard() {
    final topPlace = _topVisitedPlaces.isNotEmpty
        ? _topVisitedPlaces.first
        : null;
    final tiedCount = _topVisitedPlaces.length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          // Left side: Total score
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('経国値', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  '$_totalScore',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Container(
            width: 1,
            height: 50,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(width: 16),
          // Right side: Most visited place
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('最も訪問した国', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                if (topPlace != null) ...[
                  Row(
                    children: [
                      Text(
                        _countryCodeToFlag(topPlace.placeCode),
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topPlace.nameJa ??
                                  topPlace.nameEn ??
                                  topPlace.placeCode,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${topPlace.visitCount}回${tiedCount > 1 ? ' (他${tiedCount - 1}国/地域)' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    'まだ訪問記録がありません',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Converts ISO 3166-1 alpha-2 country code to flag emoji
  String _countryCodeToFlag(String countryCode) {
    if (countryCode.length != 2) return '🏳️';
    final upper = countryCode.toUpperCase();
    final flag = String.fromCharCodes(
      upper.codeUnits.map((c) => c - 0x41 + 0x1F1E6),
    );
    return flag;
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
                // Stats summary card
                _buildStatsCard(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                // Banner ad at bottom
                const SafeArea(top: false, child: AdaptiveBannerAdWidget()),
              ],
            ),
    );
  }
}

class _TopVisitedPlace {
  _TopVisitedPlace({
    required this.placeCode,
    required this.visitCount,
    this.nameJa,
    this.nameEn,
  });

  final String placeCode;
  final int visitCount;
  final String? nameJa;
  final String? nameEn;
}

class _TripView implements TripSortable {
  _TripView({
    required this.visit,
    required this.place,
    required this.tags,
    required this.searchTokens,
  });

  factory _TripView.fromItem(TripListItem item) {
    final tokens = <String>{
      normalizeText(item.visit.title),
      normalizeText(item.place.nameJa ?? ''),
      normalizeText(item.place.nameEn ?? ''),
      normalizeText(item.place.code),
      ...item.place.aliases.map(normalizeText),
      ...item.tags.map((tag) => normalizeText(tag.name)),
    }..removeWhere((token) => token.isEmpty);
    return _TripView(
      visit: item.visit,
      place: item.place,
      tags: item.tags,
      searchTokens: tokens,
    );
  }

  @override
  final VisitRecord visit;
  final TripPlaceInfo place;
  final List<TagRecord> tags;
  final Set<String> searchTokens;

  String? get placeLabel {
    return place.nameJa ?? place.nameEn;
  }

  @override
  String? get placeNameJa => place.nameJa;

  @override
  String? get placeNameEn => place.nameEn;

  @override
  int get placeMaxLevel => place.maxLevel;

  @override
  int get placeVisitCount => place.visitCount;

  bool matchesQuery(String query) {
    if (searchTokens.isEmpty) {
      return normalizeText(visit.title).contains(query);
    }
    return searchTokens.any((token) => token.contains(query));
  }
}
