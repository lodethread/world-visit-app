import 'package:flutter/material.dart';

import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
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
  final TextEditingController _searchController = TextEditingController();
  List<_TripView> _trips = [];
  List<_TripView> _filtered = [];
  Database? _db;
  late VisitRepository _visitRepository;
  late TagRepository _tagRepository;
  bool _loading = true;
  final Set<int> _levelFilters = {};
  final Set<String> _tagFilters = {};

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

    final placeRows = await db.query('place');
    final aliasRows = await db.query('place_alias');
    final visitRows = await db.query('visit');
    final tagRows = await db.query('tag');
    final visitTagRows = await db.query('visit_tag');

    final places = {
      for (final row in placeRows)
        row['place_code'] as String: _PlaceInfo(
          code: row['place_code'] as String,
          nameJa: row['name_ja'] as String,
          nameEn: row['name_en'] as String,
        ),
    };
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

    trips.sort((a, b) => compareVisitRecords(a.visit, b.visit));

    setState(() {
      _trips = trips;
      _filtered = trips;
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
    final query = normalizeText(_searchController.text);
    final filtered = _trips.where((trip) {
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
    filtered.sort((a, b) => compareVisitRecords(a.visit, b.visit));
    setState(() => _filtered = filtered);
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

class _TripView {
  _TripView({
    required this.visit,
    required this.place,
    required this.tags,
    required this.searchTokens,
  });

  final VisitRecord visit;
  final _PlaceInfo? place;
  final List<TagRecord> tags;
  final Set<String> searchTokens;

  String? get placeLabel {
    if (place == null) return null;
    return place!.nameJa;
  }

  bool matchesQuery(String query) {
    if (searchTokens.isEmpty) {
      return normalizeText(visit.title).contains(query);
    }
    return searchTokens.any((token) => token.contains(query));
  }
}

class _PlaceInfo {
  _PlaceInfo({required this.code, required this.nameJa, required this.nameEn});

  final String code;
  final String nameJa;
  final String nameEn;
}
