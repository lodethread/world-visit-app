import 'package:flutter/material.dart';

class FlatMapUnderConstruction extends StatelessWidget {
  const FlatMapUnderConstruction({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Flat Map (Under construction)',
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '平面地図は現在調整中です。Globe表示をご利用ください。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onExit,
              icon: const Icon(Icons.public),
              label: const Text('Globeに切替'),
            ),
          ],
        ),
      ),
    );
  }
}
