import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:world_visit_app/features/import_export/application/import_export_service.dart';
import 'package:world_visit_app/features/import_export/ui/import_flow_page.dart';

class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  late final ImportExportService _service;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _service = ImportExportService();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _exportJson() async {
    await _runTask(() async {
      final file = await _service.exportJson();
      await Share.shareXFiles([XFile(file.path)], text: 'JSON export ready');
      _showMessage('JSONを書き出しました: ${file.path}');
    });
  }

  Future<void> _exportCsv() async {
    await _runTask(() async {
      final file = await _service.exportCsv();
      await Share.shareXFiles([XFile(file.path)], text: 'CSV export ready');
      _showMessage('CSVを書き出しました: ${file.path}');
    });
  }

  Future<void> _runTask(Future<void> Function() task) async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    try {
      await task();
    } catch (error) {
      _showMessage('処理に失敗しました: $error');
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openImportFlow(ImportFileFormat format) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportFlowPage(format: format, service: _service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Export',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRunning ? null : _exportJson,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('JSON Export'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isRunning ? null : _exportCsv,
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('CSV Export'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('書き出したファイルは共有アプリで送信できます。'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Import',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openImportFlow(ImportFileFormat.json),
                        icon: const Icon(Icons.description),
                        label: const Text('JSON Import'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openImportFlow(ImportFileFormat.csv),
                        icon: const Icon(Icons.table_rows),
                        label: const Text('CSV Import'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('ファイルを選択してPreflight→Preview→実行まで案内します。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
