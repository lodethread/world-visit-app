import 'package:world_visit_app/features/map/data/flat_map_loader.dart';

/// Ensures that decoded datasets contain usable geometries/polygons.
class MapDatasetGuard {
  const MapDatasetGuard._();

  static void ensureUsable(FlatMapDataset dataset, {required String label}) {
    if (dataset.geometries.isEmpty) {
      throw MapDatasetException('$label dataset has no geometries.');
    }
    if (dataset.polygons.isEmpty) {
      throw MapDatasetException('$label dataset has no polygons.');
    }
  }
}

class MapDatasetException implements Exception {
  const MapDatasetException(this.message);

  final String message;

  @override
  String toString() => message;
}
