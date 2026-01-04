import 'dart:ui';

/// Simple uniform grid spatial index for hit testing (world coordinates 0-1).
class SpatialIndex<T> {
  SpatialIndex({int cellCount = 64})
    : assert(cellCount > 0),
      _cellCount = cellCount;

  final int _cellCount;
  final Map<int, List<_SpatialEntry<T>>> _cells = {};

  void insert(Rect bounds, T value) {
    if (bounds.isEmpty) {
      return;
    }
    final norm = Rect.fromLTRB(
      bounds.left.clamp(0.0, 1.0),
      bounds.top.clamp(0.0, 1.0),
      bounds.right.clamp(0.0, 1.0),
      bounds.bottom.clamp(0.0, 1.0),
    );
    final minX = _toIndex(norm.left);
    final maxX = _toIndex(norm.right);
    final minY = _toIndex(norm.top);
    final maxY = _toIndex(norm.bottom);
    final entry = _SpatialEntry(bounds, value);
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        _cells.putIfAbsent(_key(x, y), () => []).add(entry);
      }
    }
  }

  Iterable<T> query(Offset point) sync* {
    final ix = _toIndex(point.dx);
    final iy = _toIndex(point.dy);
    final seen = <T>{};
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final nx = ix + dx;
        final ny = iy + dy;
        if (nx < 0 || ny < 0 || nx >= _cellCount || ny >= _cellCount) {
          continue;
        }
        final cell = _cells[_key(nx, ny)];
        if (cell == null) continue;
        for (final entry in cell) {
          if (entry.bounds.contains(point) && seen.add(entry.value)) {
            yield entry.value;
          }
        }
      }
    }
  }

  int _key(int x, int y) => y * _cellCount + x;

  int _toIndex(double value) {
    final clamped = value.clamp(0.0, 0.999999999);
    return (clamped * _cellCount).floor();
  }
}

class _SpatialEntry<T> {
  const _SpatialEntry(this.bounds, this.value);

  final Rect bounds;
  final T value;
}
