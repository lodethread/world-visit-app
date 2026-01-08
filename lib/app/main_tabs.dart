import 'package:flutter/material.dart';
import 'package:world_visit_app/app/theme/app_theme.dart';
import 'package:world_visit_app/features/map/map_page.dart';
import 'package:world_visit_app/features/settings/settings_page.dart';
import 'package:world_visit_app/features/trips/trips_page.dart';

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _currentIndex = 0;
  final GlobalKey<MapPageState> _mapKey = GlobalKey<MapPageState>();
  final GlobalKey<TripsPageState> _tripsKey = GlobalKey<TripsPageState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      MapPage(key: _mapKey),
      TripsPage(key: _tripsKey),
      const SettingsPage(),
    ];
  }

  void _onDestinationSelected(int index) {
    final previousIndex = _currentIndex;
    setState(() => _currentIndex = index);
    // Refresh map when switching to map tab from another tab
    if (index == 0 && previousIndex != 0) {
      _mapKey.currentState?.refresh();
    }
    // Refresh trips when switching to trips tab from another tab
    if (index == 1 && previousIndex != 1) {
      _tripsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onDestinationSelected,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.public_outlined),
              selectedIcon: Icon(Icons.public),
              label: 'Globe',
            ),
            NavigationDestination(
              icon: Icon(Icons.flight_takeoff_outlined),
              selectedIcon: Icon(Icons.flight_takeoff),
              label: 'Trips',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
