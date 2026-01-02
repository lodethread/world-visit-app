import 'package:flutter/material.dart';
import 'package:world_visit_app/app/main_tabs.dart';

class WorldVisitApp extends StatelessWidget {
  const WorldVisitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'World Visit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainTabs(),
    );
  }
}
