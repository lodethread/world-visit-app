import 'package:flutter/material.dart';

import 'package:world_visit_app/data/db/visit_repository.dart';

class MapSelectionSheetData {
  const MapSelectionSheetData({
    required this.placeCode,
    required this.displayName,
    required this.level,
    required this.levelLabel,
    required this.levelColor,
    required this.visitCount,
    this.latestVisit,
  });

  final String placeCode;
  final String displayName;
  final int level;
  final String levelLabel;
  final Color levelColor;
  final int visitCount;
  final VisitRecord? latestVisit;
}

class MapSelectionSheet extends StatelessWidget {
  const MapSelectionSheet({
    super.key,
    required this.controller,
    required this.data,
    required this.onAddVisit,
    required this.onDuplicateVisit,
    required this.onOpenDetail,
    required this.onClose,
  });

  final DraggableScrollableController controller;
  final MapSelectionSheetData data;
  final VoidCallback onAddVisit;
  final VoidCallback onDuplicateVisit;
  final VoidCallback onOpenDetail;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: 0.22,
      minChildSize: 0.16,
      maxChildSize: 0.6,
      snap: true,
      snapSizes: const [0.22, 0.4, 0.6],
      builder: (context, scrollController) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          top: false,
          child: Material(
            elevation: 12,
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.displayName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${data.placeCode} · Lv.${data.level} / ${data.levelLabel}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                      tooltip: '閉じる',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _LevelChip(color: data.levelColor, level: data.level),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('訪問レベル'),
                        Text(
                          data.levelLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('訪問回数'),
                        Text(
                          '${data.visitCount}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('直近Visit', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (data.latestVisit != null)
                  _LatestVisitSummary(visit: data.latestVisit!)
                else
                  Text(
                    '直近のVisit情報がありません',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAddVisit,
                  icon: const Icon(Icons.add),
                  label: const Text('旅行追加'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onDuplicateVisit,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('直前複製'),
                ),
                TextButton.icon(
                  onPressed: onOpenDetail,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('詳細'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.color, required this.level});

  final Color color;
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        'Lv.$level',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _LatestVisitSummary extends StatelessWidget {
  const _LatestVisitSummary({required this.visit});

  final VisitRecord visit;

  String _formatRange() {
    final start = visit.startDate;
    final end = visit.endDate;
    if (start == null && end == null) {
      return '日付情報なし';
    }
    if (start != null && end != null) {
      if (start == end) return start;
      return '$start - $end';
    }
    return start ?? end ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(visit.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(_formatRange(), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Lv.${visit.level}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
