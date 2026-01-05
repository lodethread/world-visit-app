import 'package:world_visit_app/data/db/visit_repository.dart';

enum TripSortOption { recent, nameEn, nameJa, score }

abstract interface class TripSortable {
  VisitRecord get visit;
  String? get placeNameJa;
  String? get placeNameEn;
  int get placeMaxLevel;
  int get placeVisitCount;
}

extension TripSortOptionLabel on TripSortOption {
  String get label {
    switch (this) {
      case TripSortOption.recent:
        return '時系列';
      case TripSortOption.nameEn:
        return '国名 (EN)';
      case TripSortOption.nameJa:
        return '国名 (JA)';
      case TripSortOption.score:
        return 'スコア';
    }
  }

  String get storageValue {
    switch (this) {
      case TripSortOption.recent:
        return 'recent';
      case TripSortOption.nameEn:
        return 'name_en';
      case TripSortOption.nameJa:
        return 'name_ja';
      case TripSortOption.score:
        return 'score';
    }
  }
}

TripSortOption? tripSortOptionFromStorage(String? raw) {
  switch (raw) {
    case 'recent':
      return TripSortOption.recent;
    case 'name_en':
      return TripSortOption.nameEn;
    case 'name_ja':
      return TripSortOption.nameJa;
    case 'score':
      return TripSortOption.score;
    default:
      return null;
  }
}

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

int compareTrips(TripSortable a, TripSortable b, TripSortOption option) {
  switch (option) {
    case TripSortOption.recent:
      return compareVisitRecords(a.visit, b.visit);
    case TripSortOption.nameEn:
      return _compareByName(
        a,
        b,
        primary: (entry) => entry.placeNameEn,
        secondary: (entry) => entry.placeNameJa,
      );
    case TripSortOption.nameJa:
      return _compareByName(
        a,
        b,
        primary: (entry) => entry.placeNameJa,
        secondary: (entry) => entry.placeNameEn,
      );
    case TripSortOption.score:
      final levelComparison = b.placeMaxLevel.compareTo(a.placeMaxLevel);
      if (levelComparison != 0) {
        return levelComparison;
      }
      final visitCountComparison = b.placeVisitCount.compareTo(
        a.placeVisitCount,
      );
      if (visitCountComparison != 0) {
        return visitCountComparison;
      }
      return _compareByName(
        a,
        b,
        primary: (entry) => entry.placeNameEn,
        secondary: (entry) => entry.placeNameJa,
      );
  }
}

int _compareByName(
  TripSortable a,
  TripSortable b, {
  required String? Function(TripSortable entry) primary,
  required String? Function(TripSortable entry) secondary,
}) {
  final nameA = _resolveName(a, primary, secondary);
  final nameB = _resolveName(b, primary, secondary);
  final cmp = nameA.compareTo(nameB);
  if (cmp != 0) {
    return cmp;
  }
  return compareVisitRecords(a.visit, b.visit);
}

String _resolveName(
  TripSortable entry,
  String? Function(TripSortable entry) primary,
  String? Function(TripSortable entry) secondary,
) {
  final primaryName = primary(entry)?.toLowerCase();
  if (primaryName != null && primaryName.isNotEmpty) {
    return primaryName;
  }
  final fallback = secondary(entry)?.toLowerCase();
  if (fallback != null && fallback.isNotEmpty) {
    return fallback;
  }
  return entry.visit.placeCode.toLowerCase();
}
