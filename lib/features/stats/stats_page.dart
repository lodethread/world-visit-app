import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/stats_repository.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _loading = true;
  int _totalScore = 0;
  Map<int, int> _levelCounts = _emptyLevelCounts();
  Database? _db;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Note: Do NOT close DB here - it's shared across the app
    super.dispose();
  }

  static Map<int, int> _emptyLevelCounts() {
    return {for (var level = 0; level <= 5; level++) level: 0};
  }

  Future<void> _load() async {
    final db = _db ?? await AppDatabase().open();
    _db ??= db;
    final repository = StatsRepository(db);
    final total = await repository.totalScore();
    final counts = await repository.levelCounts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _totalScore = total;
      _levelCounts = {
        for (var level = 0; level <= 5; level++) level: counts[level] ?? 0,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final levelTiles = [
      for (var level = 0; level <= 5; level++)
        ListTile(
          leading: CircleAvatar(child: Text(level.toString())),
          title: Text('Level $level'),
          trailing: Text(
            '${_levelCounts[level] ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Total score'),
            subtitle: const Text('Σ place_stats.max_level'),
            trailing: Text(
              '$_totalScore',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListTile(
                title: Text('Level distribution'),
                subtitle: Text('Number of places per level (0-5)'),
              ),
              const Divider(height: 0),
              ...levelTiles,
            ],
          ),
        ),
      ],
    );
  }
}
