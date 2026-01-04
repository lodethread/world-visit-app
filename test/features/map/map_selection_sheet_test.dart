import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/map/widgets/map_selection_sheet.dart';

void main() {
  group('MapSelectionSheet', () {
    testWidgets('shows bottom sheet content for selected place', (
      tester,
    ) async {
      final controller = DraggableScrollableController();
      const data = MapSelectionSheetData(
        placeCode: 'JP',
        displayName: '日本',
        level: 3,
        levelLabel: '訪問（宿泊なし）',
        levelColor: Color(0xFF4CAF50),
        visitCount: 5,
        latestVisit: VisitRecord(
          visitId: 'v1',
          placeCode: 'JP',
          title: 'Tokyo Stop',
          startDate: '2024-01-01',
          endDate: '2024-01-05',
          level: 3,
          note: null,
          createdAt: 0,
          updatedAt: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapSelectionSheet(
              controller: controller,
              data: data,
              onAddVisit: _noop,
              onDuplicateVisit: _noop,
              onOpenDetail: _noop,
              onClose: _noop,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('日本'), findsOneWidget);
      expect(find.text('旅行追加'), findsOneWidget);
      expect(find.text('直前複製'), findsOneWidget);
      expect(find.text('Tokyo Stop'), findsOneWidget);
    });
  });
}

void _noop() {}
