import 'package:flutter/material.dart';
import 'package:world_visit_app/app/bootstrap/bootstrap_gate.dart';
import 'package:world_visit_app/app/bootstrap/place_sync_service.dart';
import 'package:world_visit_app/app/main_tabs.dart';
import 'package:world_visit_app/app/theme/app_theme.dart';

class WorldVisitApp extends StatelessWidget {
  const WorldVisitApp({super.key, this.syncService});

  final PlaceSyncService? syncService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'World Visit',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: BootstrapGate(service: syncService, child: const MainTabs()),
    );
  }
}
