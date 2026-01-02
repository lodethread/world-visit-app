import 'package:flutter/material.dart';

import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/place_picker/place_picker_page.dart';
import 'package:world_visit_app/features/tag/ui/tag_picker_sheet.dart';

class VisitEditorPage extends StatefulWidget {
  const VisitEditorPage({
    super.key,
    this.initialVisit,
    this.initialPlaceCode,
    this.initialTags,
    this.initialTitle,
    this.initialLevel,
    this.initialNote,
  });

  final VisitRecord? initialVisit;
  final String? initialPlaceCode;
  final List<TagRecord>? initialTags;
  final String? initialTitle;
  final int? initialLevel;
  final String? initialNote;

  @override
  State<VisitEditorPage> createState() => _VisitEditorPageState();
}

class _VisitEditorPageState extends State<VisitEditorPage> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  int _level = 3;
  String? _placeCode;
  VisitRecord? _existing;
  List<TagRecord> _selectedTags = [];
  bool _loading = true;
  Map<String, String> _placeNames = {};

  Database? _db;
  late VisitRepository _visitRepository;
  late TagRepository _tagRepository;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = await AppDatabase().open();
    _db = db;
    _visitRepository = VisitRepository(db);
    _tagRepository = TagRepository(db);
    final placeRows = await db.query('place');
    final placeNames = {
      for (final row in placeRows)
        row['place_code'] as String: row['name_ja'] as String,
    };

    VisitRecord? visit = widget.initialVisit;
    List<TagRecord> tags = widget.initialTags ?? [];
    if (visit != null) {
      tags = await _tagRepository.listByVisitId(visit.visitId);
    }

    setState(() {
      _existing = visit;
      _selectedTags = tags;
      _placeCode = visit?.placeCode ?? widget.initialPlaceCode;
      _titleController.text = visit?.title ?? widget.initialTitle ?? '';
      _noteController.text = visit?.note ?? widget.initialNote ?? '';
      _startDateController.text = visit?.startDate ?? '';
      _endDateController.text = visit?.endDate ?? '';
      _level = visit?.level ?? widget.initialLevel ?? 3;
      _loading = false;
      _placeNames = placeNames;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _db?.close();
    super.dispose();
  }

  Future<void> _pickPlace() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PlacePickerPage()));
    if (code != null) {
      setState(() => _placeCode = code);
    }
  }

  Future<void> _pickTags() async {
    final tags = await TagPickerSheet.show(
      context,
      repository: _tagRepository,
      initialSelection: _selectedTags,
    );
    if (tags != null) {
      setState(() => _selectedTags = tags);
    }
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final now = DateTime.now();
    final initialDate = DateTime.tryParse(controller.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = picked.toIso8601String().substring(0, 10);
    }
  }

  Future<void> _save() async {
    final placeCode = _placeCode;
    if (placeCode == null) {
      _showMessage('Placeを選択してください');
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('タイトルは必須です');
      return;
    }
    final level = _level;
    final startDate = _startDateController.text.trim().isEmpty
        ? null
        : _startDateController.text.trim();
    final endDate = _endDateController.text.trim().isEmpty
        ? null
        : _endDateController.text.trim();
    if (startDate != null &&
        endDate != null &&
        startDate.compareTo(endDate) > 0) {
      _showMessage('日付の前後関係が不正です');
      return;
    }
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    if (_existing == null) {
      final record = await _visitRepository.createVisit(
        placeCode: placeCode,
        title: title,
        startDate: startDate,
        endDate: endDate,
        level: level,
        note: note,
      );
      await _visitRepository.setTagsForVisit(
        record.visitId,
        _selectedTags.map((e) => e.tagId).toList(),
      );
    } else {
      final updated = _existing!.copyWith(
        placeCode: placeCode,
        title: title,
        startDate: startDate,
        endDate: endDate,
        level: level,
        note: note,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _visitRepository.updateVisit(updated);
      await _visitRepository.setTagsForVisit(
        updated.visitId,
        _selectedTags.map((e) => e.tagId).toList(),
      );
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除しますか?'),
        content: const Text('この訪問記録を削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _visitRepository.deleteVisit(_existing!.visitId);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Visit追加' : 'Visit編集'),
        actions: [
          if (_existing != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _placeCode == null
                          ? 'Place未選択'
                          : _placeNames[_placeCode] ?? _placeCode!,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickPlace,
                  ),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'タイトル'),
                  ),
                  Row(
                    children: [
                      const Text('レベル'),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 5,
                          divisions: 4,
                          value: _level.toDouble(),
                          label: '$_level',
                          onChanged: (value) =>
                              setState(() => _level = value.round()),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _startDateController,
                    decoration: const InputDecoration(
                      labelText: '開始日 (YYYY-MM-DD)',
                    ),
                    readOnly: true,
                    onTap: () => _selectDate(_startDateController),
                  ),
                  TextField(
                    controller: _endDateController,
                    decoration: const InputDecoration(
                      labelText: '終了日 (YYYY-MM-DD)',
                    ),
                    readOnly: true,
                    onTap: () => _selectDate(_endDateController),
                  ),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: 'メモ'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _selectedTags
                        .map(
                          (tag) => Chip(
                            label: Text(tag.name),
                            onDeleted: () =>
                                setState(() => _selectedTags.remove(tag)),
                          ),
                        )
                        .toList(),
                  ),
                  TextButton.icon(
                    onPressed: _pickTags,
                    icon: const Icon(Icons.local_offer_outlined),
                    label: const Text('タグを選択'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
            ),
    );
  }
}
