import 'package:flutter/material.dart';

import 'package:world_visit_app/app/bootstrap/place_sync_service.dart';

class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key, required this.child, this.service});

  final Widget child;
  final PlaceSyncService? service;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  late Future<void> _future;
  late final PlaceSyncService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PlaceSyncService();
    _future = _service.syncIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('データ同期に失敗しました'),
                  const SizedBox(height: 12),
                  Text('${snapshot.error}'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _future = _service.syncIfNeeded();
                      });
                    },
                    child: const Text('再試行'),
                  ),
                ],
              ),
            ),
          );
        }
        return widget.child;
      },
    );
  }
}
