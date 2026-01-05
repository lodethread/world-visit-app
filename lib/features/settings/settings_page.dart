import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:world_visit_app/features/import_export/ui/data_management_page.dart';
import 'package:world_visit_app/features/place/ui/place_detail_page.dart';
import 'package:world_visit_app/features/place_picker/place_picker_page.dart';
import 'package:world_visit_app/features/settings/data_sources_page.dart';
import 'package:world_visit_app/features/stats/stats_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(title: Text('General')),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Browse places'),
            subtitle: const Text('国/地域一覧から詳細を開く'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPlacePicker(context),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Stats'),
            subtitle: const Text('経国値とレベル分布'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const StatsPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Data management'),
            subtitle: const Text('Import/Export (JSON & CSV)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataManagementPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About / Data sources'),
            subtitle: const Text('Natural Earth / world-atlas / tool scripts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataSourcesPage()),
              );
            },
          ),
          if (!kReleaseMode) ...[
            const Divider(height: 32),
            const ListTile(title: Text('Debug')),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Pick place'),
              subtitle: const Text('Place詳細表示を確認'),
              onTap: () => _openPlacePicker(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openPlacePicker(BuildContext context) async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => const PlacePickerPage()),
    );
    if (result != null) {
      await navigator.push(
        MaterialPageRoute(builder: (_) => PlaceDetailPage(placeCode: result)),
      );
    }
  }
}
