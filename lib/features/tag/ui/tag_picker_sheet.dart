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
  bool _creatingTag = false;
  String? _loadError;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialSelection.map((e) => e.tagId).toSet();
    _newTagController.addListener(_handleNewTagChanged);
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final tags = await widget.repository.listAll();
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _allTags = tags;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = 'タグの読み込みに失敗しました';
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newTagController.dispose();
    super.dispose();
  }

  void _handleNewTagChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
    if (name.isEmpty || _creatingTag) return;
    setState(() => _creatingTag = true);
    try {
      final tag = await widget.repository.getOrCreateByName(name);
      if (!mounted) return;
      _newTagController.clear();
      await _load();
      if (!mounted) return;
      setState(() {
        _selectedIds.add(tag.tagId);
      });
    } catch (error) {
      _showMessage('タグの追加に失敗しました');
    } finally {
      if (mounted) {
        setState(() => _creatingTag = false);
      }
    }
  }

  bool get _canSubmitNewTag {
    return _newTagController.text.trim().isNotEmpty && !_creatingTag;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final filteredTags = _filteredTags;
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
                      onPressed: _canSubmitNewTag ? _createTag : null,
                      child: _creatingTag
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('追加'),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('再読み込み'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (filteredTags.isEmpty)
                const Expanded(child: Center(child: Text('タグがありません')))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredTags.length,
                    itemBuilder: (context, index) {
                      final tag = filteredTags[index];
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
