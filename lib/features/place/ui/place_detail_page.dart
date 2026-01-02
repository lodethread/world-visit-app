import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/place/data/place_detail_loader.dart';
import 'package:world_visit_app/features/visit/ui/visit_editor_page.dart';

typedef DatabaseBuilder = Future<Database> Function();

class PlaceDetailPage extends StatefulWidget {
  const PlaceDetailPage({
    super.key,
    required this.placeCode,
    this.databaseBuilder,
  });

  final String placeCode;
  final DatabaseBuilder? databaseBuilder;

  @override
  State<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends State<PlaceDetailPage> {
  Database? _db;
  VisitRepository? _visitRepo;
  TagRepository? _tagRepo;
  PlaceDetailData? _data;
  bool _loading = true;
  String? _error;
  bool _ownsDb = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final builder = widget.databaseBuilder;
    final db = await (builder?.call() ?? AppDatabase().open());
    _db = db;
    _ownsDb = builder == null;
    _visitRepo ??= VisitRepository(db);
    _tagRepo ??= TagRepository(db);

    final detail = await loadPlaceDetail(db, widget.placeCode);
    if (detail == null) {
      if (!mounted) return;
      setState(() {
        _error = '指定されたPlaceが見つかりません';
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _data = detail;
      _loading = false;
    });
  }

  @override
  void dispose() {
    if (_ownsDb) {
      _db?.close();
    }
    super.dispose();
  }

  Future<void> _addVisit() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditorPage(initialPlaceCode: widget.placeCode),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _duplicateLatest() async {
    final repo = _visitRepo;
    if (repo == null) return;
    final latest = await repo.latestVisit();
    if (latest == null) {
      if (!mounted) return;
      _showMessage('複製できる旅行がありません');
      return;
    }
    final tags = await _tagRepo!.listByVisitId(latest.visitId);
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditorPage(
          initialPlaceCode: widget.placeCode,
          initialTitle: latest.title,
          initialLevel: latest.level,
          initialNote: latest.note,
          initialTags: tags,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _editVisit(VisitRecord visit) async {
    final tags = await _tagRepo!.listByVisitId(visit.visitId);
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditorPage(initialVisit: visit, initialTags: tags),
      ),
    );
    if (mounted) await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: Text(widget.placeCode)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(data!.nameJa),
                  subtitle: Text(data.nameEn),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _StatTile(
                        label: 'Max Level',
                        value: data.maxLevel.toString(),
                      ),
                      const SizedBox(width: 16),
                      _StatTile(
                        label: 'Visits',
                        value: data.visitCount.toString(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OverflowBar(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _addVisit,
                        icon: const Icon(Icons.add),
                        label: const Text('旅行追加'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _duplicateLatest,
                        icon: const Icon(Icons.copy),
                        label: const Text('直前旅行を複製'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: data.visits.isEmpty
                      ? const Center(child: Text('Visitがありません'))
                      : ListView.separated(
                          itemCount: data.visits.length,
                          separatorBuilder: (context, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final visit = data.visits[index];
                            return ListTile(
                              title: Text(visit.visit.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (visit.visit.startDate != null)
                                    Text(
                                      visit.visit.endDate == null
                                          ? visit.visit.startDate!
                                          : '${visit.visit.startDate} - ${visit.visit.endDate}',
                                    ),
                                  if (visit.tags.isNotEmpty)
                                    Text(
                                      visit.tags.join(', '),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                              trailing: Text('Lv.${visit.visit.level}'),
                              onTap: () => _editVisit(visit.visit),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}
