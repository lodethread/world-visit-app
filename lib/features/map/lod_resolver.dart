enum MapLod {
  /// 110m geometry assets (coarse, low detail).
  coarse110m,

  /// 50m geometry assets (fine, high detail).
  fine50m,
}

class MapLodResolver {
  const MapLodResolver({
    this.highDetailThreshold = 90.0,
    this.lowDetailThreshold = 100.0,
  }) : assert(highDetailThreshold < lowDetailThreshold);

  final double highDetailThreshold;
  final double lowDetailThreshold;

  MapLod resolve(double lonSpan, MapLod current) {
    if (lonSpan > lowDetailThreshold) {
      return MapLod.coarse110m;
    }
    if (lonSpan < highDetailThreshold) {
      return MapLod.fine50m;
    }
    return current;
  }
}
