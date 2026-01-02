import 'package:world_visit_app/data/db/visit_repository.dart';

int compareVisitRecords(VisitRecord a, VisitRecord b) {
  final aStart = a.startDate;
  final bStart = b.startDate;
  if (aStart != null && bStart != null) {
    final cmp = bStart.compareTo(aStart);
    if (cmp != 0) return cmp;
  } else if (aStart != null) {
    return -1;
  } else if (bStart != null) {
    return 1;
  }
  return b.createdAt.compareTo(a.createdAt);
}
