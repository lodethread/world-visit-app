import 'package:flutter/material.dart';

import 'package:world_visit_app/data/db/tag_repository.dart';

class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.repository,
    required this.initialSelection,
  });

  final TagRepository repository;
  final List<TagRecord> initialSelection;

  static Future<List<TagRecord>?> show(
    BuildContext context, {
    required TagRepository repository,
    required List<TagRecord> initialSelection,
  }) {
    return showModalBottomSheet<List<TagRecord>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TagPickerSheet(
        repository: repository,
        initialSelection: initialSelection,
      ),
    );
  }

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newTagController = TextEditingController();
  late Set<String> _selectedIds;
  List<TagRecord> _allTags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialSelection.map((e) => e.tagId).toSet();
    _load();
  }

  Future<void> _load() async {
    final tags = await widget.repository.listAll();
    setState(() {
      _allTags = tags;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newTagController.dispose();
    super.dispose();
  }

  List<TagRecord> get _filteredTags {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _allTags;
    return _allTags
        .where((tag) => tag.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    final tag = await widget.repository.getOrCreateByName(name);
    _newTagController.clear();
    await _load();
    setState(() {
      _selectedIds.add(tag.tagId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const ListTile(title: Text('タグを選択')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'タグ検索',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagController,
                        decoration: const InputDecoration(hintText: '新規タグ名'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _createTag,
                      child: const Text('追加'),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredTags.length,
                    itemBuilder: (context, index) {
                      final tag = _filteredTags[index];
                      final selected = _selectedIds.contains(tag.tagId);
                      return CheckboxListTile(
                        value: selected,
                        title: Text(tag.name),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedIds.add(tag.tagId);
                            } else {
                              _selectedIds.remove(tag.tagId);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('キャンセル'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        final selected = _allTags
                            .where((tag) => _selectedIds.contains(tag.tagId))
                            .toList();
                        Navigator.of(context).pop(selected);
                      },
                      child: const Text('決定'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
