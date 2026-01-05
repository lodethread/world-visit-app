import 'package:flutter/material.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/util/normalize.dart';

import 'package:sqflite/sqflite.dart';

class PlacePickerPage extends StatefulWidget {
  const PlacePickerPage({super.key});

  @override
  State<PlacePickerPage> createState() => _PlacePickerPageState();
}

class _PlacePickerPageState extends State<PlacePickerPage> {
  final TextEditingController _controller = TextEditingController();
  final List<_PlaceEntry> _entries = [];
  List<_PlaceEntry> _results = [];
  Database? _db;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase().open();
    final placeRows = await db.query('place');
    final aliasRows = await db.query('place_alias');
    final statsRows = await db.query('place_stats');
    _db = db;

    final aliases = <String, List<String>>{};
    for (final row in aliasRows) {
      final code = row['place_code'] as String;
      final alias = row['alias'] as String;
      aliases.putIfAbsent(code, () => []).add(alias);
    }

    final stats = <String, String?>{};
    for (final row in statsRows) {
      stats[row['place_code'] as String] = row['last_visit_date'] as String?;
    }

    _entries.clear();
    for (final row in placeRows) {
      final code = row['place_code'] as String;
      final entry = _PlaceEntry(
        placeCode: code,
        nameJa: row['name_ja'] as String,
        nameEn: row['name_en'] as String,
        sortOrder: row['sort_order'] as int,
        tokens: {
          normalizeText(row['name_ja'] as String),
          normalizeText(row['name_en'] as String),
          for (final alias in aliases[code] ?? const []) normalizeText(alias),
        }..removeWhere((element) => element.isEmpty),
        lastVisitDate: stats[code],
      );
      _entries.add(entry);
    }

    _entries.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    setState(() {
      _loading = false;
      _results = _defaultResults();
    });
  }

  List<_PlaceEntry> _defaultResults() {
    final recents = _entries.where((e) => e.lastVisitDate != null).toList()
      ..sort((a, b) => b.lastVisitDate!.compareTo(a.lastVisitDate!));
    final output = <_PlaceEntry>[];
    output.addAll(recents.take(10));
    for (final entry in _entries) {
      if (!output.contains(entry)) {
        output.add(entry);
      }
    }
    return output;
  }

  void _onQueryChanged(String value) {
    final query = normalizeText(value);
    if (query.isEmpty) {
      setState(() => _results = _defaultResults());
      return;
    }

    final matches = <_MatchResult>[];
    for (final entry in _entries) {
      final match = entry.match(query);
      if (match != null) {
        matches.add(match);
      }
    }
    matches.sort();
    setState(() => _results = matches.map((e) => e.entry).toList());
  }

  @override
  void dispose() {
    _controller.dispose();
    // Note: Do NOT close DB here - it's shared across the app
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Place Picker')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '国・地域を検索',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _controller.clear();
                                _onQueryChanged('');
                              },
                            ),
                    ),
                    onChanged: _onQueryChanged,
                  ),
                ),
                Expanded(
                  child: _results.isEmpty
                      ? const Center(child: Text('該当する場所がありません'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final entry = _results[index];
                            return ListTile(
                              title: Text(entry.nameJa),
                              subtitle: Text(entry.nameEn),
                              trailing: entry.lastVisitDate == null
                                  ? null
                                  : Text(entry.lastVisitDate!),
                              onTap: () {
                                Navigator.of(context).pop(entry.placeCode);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _PlaceEntry {
  const _PlaceEntry({
    required this.placeCode,
    required this.nameJa,
    required this.nameEn,
    required this.sortOrder,
    required this.tokens,
    required this.lastVisitDate,
  });

  final String placeCode;
  final String nameJa;
  final String nameEn;
  final int sortOrder;
  final Set<String> tokens;
  final String? lastVisitDate;

  _MatchResult? match(String query) {
    if (tokens.isEmpty) return null;
    if (tokens.contains(query)) {
      return _MatchResult(this, _MatchRank.exact);
    }
    if (tokens.any((token) => token.startsWith(query))) {
      return _MatchResult(this, _MatchRank.prefix);
    }
    if (tokens.any((token) => token.contains(query))) {
      return _MatchResult(this, _MatchRank.substring);
    }
    return null;
  }
}

enum _MatchRank { exact, prefix, substring }

class _MatchResult implements Comparable<_MatchResult> {
  const _MatchResult(this.entry, this.rank);

  final _PlaceEntry entry;
  final _MatchRank rank;

  @override
  int compareTo(_MatchResult other) {
    final rankCompare = rank.index.compareTo(other.rank.index);
    if (rankCompare != 0) return rankCompare;
    final sortCompare = entry.sortOrder.compareTo(other.entry.sortOrder);
    if (sortCompare != 0) return sortCompare;
    return entry.nameJa.compareTo(other.entry.nameJa);
  }
}
