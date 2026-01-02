import 'package:flutter/material.dart';

import 'package:world_visit_app/features/import_export/ui/data_management_page.dart';

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
        ],
      ),
    );
  }
}
