import 'package:flutter/material.dart';

class MapLegendEntry {
  const MapLegendEntry({
    required this.levelLabel,
    required this.description,
    required this.color,
  });

  final String levelLabel;
  final String description;
  final Color color;
}

class MapLegendOverlay extends StatefulWidget {
  const MapLegendOverlay({super.key, required this.entries});

  final List<MapLegendEntry> entries;

  @override
  State<MapLegendOverlay> createState() => _MapLegendOverlayState();
}

class _MapLegendOverlayState extends State<MapLegendOverlay> {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: !_expanded
              ? const SizedBox.shrink()
              : _LegendCard(
                  key: const ValueKey('legend-card'),
                  entries: widget.entries,
                  onClose: _toggle,
                ),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'mapLegendFab',
          backgroundColor: Colors.black.withValues(alpha: 0.6),
          foregroundColor: Colors.white,
          onPressed: _toggle,
          tooltip: _expanded ? '凡例を閉じる' : '凡例を開く',
          child: Icon(_expanded ? Icons.close : Icons.info_outline),
        ),
      ],
    );
  }
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({super.key, required this.entries, required this.onClose});

  final List<MapLegendEntry> entries;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Legend',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: onClose,
                color: Colors.white70,
                icon: const Icon(Icons.close),
                tooltip: '凡例を閉じる',
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in entries) ...[
            _LegendItem(entry: entry),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.entry});

  final MapLegendEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: entry.color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.levelLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.description,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
