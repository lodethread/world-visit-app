import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/trips/trip_sort.dart';

void main() {
  test('compareVisitRecords sorts start_date desc and then created_at', () {
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

  test('compareTrips sorts by English name', () {
    final a = _FakeTrip(
      visit: _visit('1', startDate: '2024-01-01'),
      nameEn: 'Canada',
      nameJa: 'カナダ',
      level: 2,
      visitCount: 3,
    );
    final b = _FakeTrip(
      visit: _visit('2', startDate: '2024-02-01'),
      nameEn: 'Brazil',
      nameJa: 'ブラジル',
      level: 1,
      visitCount: 1,
    );
    final c = _FakeTrip(
      visit: _visit('3', startDate: '2023-12-01'),
      nameEn: 'Denmark',
      nameJa: 'デンマーク',
      level: 5,
      visitCount: 10,
    );
    final list = [a, b, c];
    list.sort((x, y) => compareTrips(x, y, TripSortOption.nameEn));
    expect(list.map((e) => e.visit.visitId), ['2', '1', '3']);
  });

  test('compareTrips sorts by score', () {
    final a = _FakeTrip(
      visit: _visit('1'),
      nameEn: 'Japan',
      nameJa: '日本',
      level: 3,
      visitCount: 5,
    );
    final b = _FakeTrip(
      visit: _visit('2'),
      nameEn: 'France',
      nameJa: 'フランス',
      level: 3,
      visitCount: 10,
    );
    final c = _FakeTrip(
      visit: _visit('3'),
      nameEn: 'Australia',
      nameJa: 'オーストラリア',
      level: 4,
      visitCount: 2,
    );
    final list = [a, b, c];
    list.sort((x, y) => compareTrips(x, y, TripSortOption.score));
    expect(list.map((e) => e.visit.visitId), ['3', '2', '1']);
  });

  test('sort option storage round trip works', () {
    for (final option in TripSortOption.values) {
      final stored = option.storageValue;
      expect(tripSortOptionFromStorage(stored), option);
    }
    expect(tripSortOptionFromStorage('unknown'), isNull);
  });
}

VisitRecord _visit(String id, {String? startDate}) {
  final parsed = int.tryParse(id) ?? 0;
  return VisitRecord(
    visitId: id,
    placeCode: 'XX$id',
    title: 'Trip $id',
    startDate: startDate,
    endDate: null,
    level: 3,
    note: null,
    createdAt: parsed,
    updatedAt: parsed,
  );
}

class _FakeTrip implements TripSortable {
  _FakeTrip({
    required this.visit,
    required String nameEn,
    required String nameJa,
    required int level,
    required int visitCount,
  }) : _nameEn = nameEn,
       _nameJa = nameJa,
       _level = level,
       _visitCount = visitCount;

  @override
  final VisitRecord visit;
  final String _nameEn;
  final String _nameJa;
  final int _level;
  final int _visitCount;

  @override
  String? get placeNameEn => _nameEn;

  @override
  String? get placeNameJa => _nameJa;

  @override
  int get placeMaxLevel => _level;

  @override
  int get placeVisitCount => _visitCount;
}
