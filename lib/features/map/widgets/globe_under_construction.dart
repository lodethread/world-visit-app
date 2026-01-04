import 'package:flutter/material.dart';

class GlobeUnderConstruction extends StatelessWidget {
  const GlobeUnderConstruction({super.key, required this.onExit});

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
            const Icon(Icons.public, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Globe (Under construction)',
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '現在は平面のみを提供しています。Globe投影は将来対応予定で、'
              'データの準備は完了しています。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onExit,
              icon: const Icon(Icons.arrow_back),
              label: const Text('戻る'),
            ),
          ],
        ),
      ),
    );
  }
}
