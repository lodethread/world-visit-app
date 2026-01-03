import 'dart:ui';

bool pointInPolygon(Offset point, List<Offset> polygon) {
  if (polygon.length < 3) {
    return false;
  }
  var inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final current = polygon[i];
    final previous = polygon[j];
    if (_pointOnSegment(point, previous, current)) {
      return true;
    }

    final intersects =
        ((current.dy > point.dy) != (previous.dy > point.dy)) &&
        (point.dx <
            (previous.dx - current.dx) *
                    (point.dy - current.dy) /
                    (previous.dy - current.dy) +
                current.dx);
    if (intersects) {
      inside = !inside;
    }
  }
  return inside;
}

bool _pointOnSegment(Offset point, Offset start, Offset end) {
  const tolerance = 1e-9;
  final cross =
      (point.dy - start.dy) * (end.dx - start.dx) -
      (point.dx - start.dx) * (end.dy - start.dy);
  if (cross.abs() > tolerance) {
    return false;
  }
  final dot =
      (point.dx - start.dx) * (end.dx - start.dx) +
      (point.dy - start.dy) * (end.dy - start.dy);
  if (dot < -tolerance) {
    return false;
  }
  final squaredLength =
      (end.dx - start.dx) * (end.dx - start.dx) +
      (end.dy - start.dy) * (end.dy - start.dy);
  if (dot - squaredLength > tolerance) {
    return false;
  }
  return true;
}
