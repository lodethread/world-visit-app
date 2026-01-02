import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:world_visit_app/features/import_export/application/import_export_service.dart';
import 'package:world_visit_app/features/import_export/model/import_issue.dart';
import 'package:world_visit_app/features/import_export/model/import_preview.dart';

enum ImportFileFormat { json, csv }

enum IssueFilter { all, errors, warnings }

class ImportFlowPage extends StatefulWidget {
  const ImportFlowPage({
    super.key,
    required this.format,
    required this.service,
  });

  final ImportFileFormat format;
  final ImportExportService service;

  @override
  State<ImportFlowPage> createState() => _ImportFlowPageState();
}

class _ImportFlowPageState extends State<ImportFlowPage> {
  ImportSession? _plan;
  ImportPreview? _preview;
  List<ImportIssue> _issues = const [];
  bool _strictMode = false;
  bool _running = false;
  bool _executed = false;
  IssueFilter _filter = IssueFilter.all;
  String? _filePath;
  String _status = 'ファイルを選択してください';

  @override
  Widget build(BuildContext context) {
    final filteredIssues = _filteredIssues();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.format == ImportFileFormat.json ? 'JSON Import' : 'CSV Import',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStepCard(
            title: '1. ファイル選択',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_status),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _running ? null : _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('ファイルを選択'),
                ),
                if (_filePath != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(_filePath!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_preview != null) _buildPreviewCard(_preview!),
          if (_plan != null) ...[
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              value: _strictMode,
              onChanged: _plan == null
                  ? null
                  : (value) => setState(() => _strictMode = value),
              title: const Text('厳格モード（エラーがあれば全体中断）'),
            ),
            ElevatedButton.icon(
              onPressed: _running ? null : _execute,
              icon: const Icon(Icons.playlist_add_check),
              label: Text(_executed ? '再実行' : '実行する'),
            ),
          ],
          const SizedBox(height: 24),
          if (_issues.isNotEmpty) ...[
            Row(
              children: [
                Text('Issues (${filteredIssues.length}/${_issues.length})'),
                const Spacer(),
                SegmentedButton<IssueFilter>(
                  segments: const [
                    ButtonSegment(value: IssueFilter.all, label: Text('All')),
                    ButtonSegment(
                      value: IssueFilter.errors,
                      label: Text('Error'),
                    ),
                    ButtonSegment(
                      value: IssueFilter.warnings,
                      label: Text('Warn'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (values) =>
                      setState(() => _filter = values.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (_, index) =>
                  _IssueTile(issue: filteredIssues[index]),
              separatorBuilder: (context, _) => const Divider(height: 1),
              itemCount: filteredIssues.length,
            ),
          ],
          if (_issues.isEmpty && _plan != null) const Text('Issueはありません。'),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _running = true;
      _status = '読み込み中...';
      _executed = false;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.format == ImportFileFormat.json
            ? const ['json']
            : const ['csv'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          _status = 'ファイルが選択されませんでした';
          _running = false;
        });
        return;
      }
      final path = result.files.single.path;
      if (path == null) {
        throw const FormatException('ファイルパスを取得できませんでした');
      }
      final data = await File(path).readAsString();
      final plan = widget.format == ImportFileFormat.json
          ? await widget.service.prepareJsonImport(data)
          : await widget.service.prepareCsvImport(data);
      setState(() {
        _plan = plan;
        _preview = plan.preview;
        _issues = plan.issues;
        _filePath = path;
        _status = 'Preflight完了';
        _running = false;
      });
    } catch (error) {
      setState(() {
        _running = false;
        _status = '読み込みに失敗しました';
      });
      _showSnack('読み込みに失敗しました: $error');
    }
  }

  Future<void> _execute() async {
    if (_plan == null) return;
    setState(() => _running = true);
    try {
      final result = await widget.service.executeImportPlan(
        _plan!,
        strictMode: _strictMode,
      );
      setState(() {
        _issues = result.issues;
        _preview = result.preview;
        _running = false;
        _executed = result.applied;
        _status = result.applied ? 'インポートが完了しました' : '厳格モードのため実行されませんでした';
      });
      if (result.applied) {
        _showSnack('インポートが完了しました');
      }
    } catch (error) {
      setState(() => _running = false);
      _showSnack('インポートに失敗しました: $error');
    }
  }

  Widget _buildStepCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ImportPreview preview) {
    final entries = [
      _PreviewEntry('総件数', preview.visitsTotal.toString()),
      _PreviewEntry('有効', preview.valid.toString()),
      _PreviewEntry('スキップ', preview.skipped.toString()),
      _PreviewEntry('Insert', preview.inserts.toString()),
      _PreviewEntry('Update', preview.updates.toString()),
      _PreviewEntry('新規タグ', preview.tagsToCreate.toString()),
      _PreviewEntry('Error', preview.errorCount.toString()),
      _PreviewEntry('Warn', preview.warningCount.toString()),
    ];
    return _buildStepCard(
      title: '2. Preview',
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: entries
            .map(
              (e) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(e.value),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  List<ImportIssue> _filteredIssues() {
    switch (_filter) {
      case IssueFilter.errors:
        return _issues
            .where((issue) => issue.severity == ImportIssueSeverity.error)
            .toList();
      case IssueFilter.warnings:
        return _issues
            .where((issue) => issue.severity == ImportIssueSeverity.warning)
            .toList();
      case IssueFilter.all:
        return _issues;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue});

  final ImportIssue issue;

  @override
  Widget build(BuildContext context) {
    final color = switch (issue.severity) {
      ImportIssueSeverity.error => Colors.red,
      ImportIssueSeverity.warning => Colors.orange,
      ImportIssueSeverity.info => Colors.blue,
    };
    return ListTile(
      leading: Icon(Icons.info_outline, color: color),
      title: Text('[${issue.code}] ${issue.message}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (issue.location != null) Text('Location: ${issue.location}'),
          if (issue.context != null)
            Text(
              issue.context!.entries
                  .map((e) => '${e.key}=${e.value}')
                  .join(', '),
            ),
        ],
      ),
    );
  }
}

class _PreviewEntry {
  const _PreviewEntry(this.label, this.value);
  final String label;
  final String value;
}
