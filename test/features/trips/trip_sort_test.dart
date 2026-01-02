import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/trips/trip_sort.dart';

void main() {
  test('compareTripView sorts start_date desc and then created_at', () {
    final visitA = VisitRecord(
      visitId: 'a',
      placeCode: 'JP',
      title: 'A',
      startDate: '2024-05-01',
      endDate: null,
      level: 3,
      note: null,
      createdAt: 1,
      updatedAt: 1,
    );
    final visitB = VisitRecord(
      visitId: 'b',
      placeCode: 'JP',
      title: 'B',
      startDate: '2024-04-01',
      endDate: null,
      level: 3,
      note: null,
      createdAt: 2,
      updatedAt: 2,
    );
    final visitC = VisitRecord(
      visitId: 'c',
      placeCode: 'JP',
      title: 'C',
      startDate: null,
      endDate: null,
      level: 3,
      note: null,
      createdAt: 10,
      updatedAt: 10,
    );
    final visitD = VisitRecord(
      visitId: 'd',
      placeCode: 'JP',
      title: 'D',
      startDate: null,
      endDate: null,
      level: 3,
      note: null,
      createdAt: 5,
      updatedAt: 5,
    );

    final list = [visitB, visitA, visitD, visitC];
    list.sort(compareVisitRecords);
    expect(list.map((e) => e.visitId), ['a', 'b', 'c', 'd']);
  });
}
