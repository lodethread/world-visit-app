import 'dart:math' as math;
import 'dart:ui';

/// Orthographic projection for rendering a 3D globe on a 2D canvas.
/// 
/// This class handles:
/// - Converting lat/lon to 3D spherical coordinates
/// - Applying rotation matrix for globe rotation
/// - Projecting 3D coordinates to 2D screen coordinates
/// - Back-face culling (hiding polygons on the far side of the globe)
class GlobeProjection {
  const GlobeProjection({
    this.rotationX = 0.0,
    this.rotationY = 0.0,
    this.scale = 1.0,
  });

  /// Rotation around the X axis (vertical tilt) in radians
  final double rotationX;

  /// Rotation around the Y axis (horizontal rotation) in radians
  final double rotationY;

  /// Scale factor for the globe
  final double scale;

  /// Creates a copy with updated rotation values
  GlobeProjection copyWith({
    double? rotationX,
    double? rotationY,
    double? scale,
  }) {
    return GlobeProjection(
      rotationX: rotationX ?? this.rotationX,
      rotationY: rotationY ?? this.rotationY,
      scale: scale ?? this.scale,
    );
  }

  /// Converts latitude and longitude to 3D Cartesian coordinates on a unit sphere.
  /// 
  /// [lat] Latitude in degrees (-90 to 90)
  /// [lon] Longitude in degrees (-180 to 180)
  /// 
  /// Returns (x, y, z) where:
  /// - x points towards longitude 0, latitude 0
  /// - y points towards the North Pole
  /// - z points towards longitude 90, latitude 0
  (double, double, double) latLonToCartesian(double lat, double lon) {
    final latRad = lat * math.pi / 180.0;
    final lonRad = lon * math.pi / 180.0;

    final cosLat = math.cos(latRad);
    final x = cosLat * math.cos(lonRad);
    final y = math.sin(latRad);
    final z = cosLat * math.sin(lonRad);

    return (x, y, z);
  }

  /// Applies rotation matrix to 3D coordinates.
  /// 
  /// First rotates around Y axis (horizontal rotation),
  /// then rotates around X axis (vertical tilt).
  (double, double, double) applyRotation(double x, double y, double z) {
    // Rotation around Y axis (horizontal rotation)
    final cosY = math.cos(rotationY);
    final sinY = math.sin(rotationY);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;
    final y1 = y;

    // Rotation around X axis (vertical tilt)
    final cosX = math.cos(rotationX);
    final sinX = math.sin(rotationX);
    final y2 = y1 * cosX - z1 * sinX;
    final z2 = y1 * sinX + z1 * cosX;
    final x2 = x1;

    return (x2, y2, z2);
  }

  /// Projects a lat/lon point to 2D screen coordinates.
  /// 
  /// [lat] Latitude in degrees
  /// [lon] Longitude in degrees
  /// [center] Center of the globe on screen
  /// [radius] Radius of the globe on screen
  /// 
  /// Returns null if the point is on the back side of the globe (not visible).
  /// Otherwise returns the 2D screen coordinates.
  Offset? project(double lat, double lon, Offset center, double radius) {
    // Convert to 3D
    final (x, y, z) = latLonToCartesian(lat, lon);

    // Apply rotation
    final (rx, ry, rz) = applyRotation(x, y, z);

    // Back-face culling: we're viewing from the positive Z direction,
    // so points with rz < 0 are on the back (not visible)
    // However, we want to see the "front" of the Earth (as if looking from outside),
    // so we check rz > 0 for visibility
    if (rz < 0) {
      return null;
    }

    // Orthographic projection: simply use x and y, ignore z
    // Note: y is flipped because screen coordinates have y increasing downward
    // Note: x is also flipped to correct the mirror effect (viewing from outside)
    final screenX = center.dx - rx * radius * scale;
    final screenY = center.dy - ry * radius * scale;

    return Offset(screenX, screenY);
  }

  /// Projects a lat/lon point to 2D, returning both the screen position and visibility.
  /// 
  /// Unlike [project], this always returns a position (for edge interpolation),
  /// along with a boolean indicating if the point is visible.
  (Offset, bool) projectWithVisibility(
    double lat,
    double lon,
    Offset center,
    double radius,
  ) {
    final (x, y, z) = latLonToCartesian(lat, lon);
    final (rx, ry, rz) = applyRotation(x, y, z);

    final screenX = center.dx - rx * radius * scale;
    final screenY = center.dy - ry * radius * scale;

    return (Offset(screenX, screenY), rz >= 0);
  }

  /// Converts normalized coordinates (0-1 range from flat map) to lat/lon.
  /// 
  /// [nx] Normalized x coordinate (0 = -180°, 1 = 180°)
  /// [ny] Normalized y coordinate (0 = 90°, 1 = -90°) - Web Mercator style
  /// 
  /// Note: This assumes simple equirectangular mapping, not Web Mercator.
  /// For Web Mercator, use [normalizedMercatorToLatLon].
  static (double, double) normalizedToLatLon(double nx, double ny) {
    final lon = (nx - 0.5) * 360.0; // -180 to 180
    final lat = (0.5 - ny) * 180.0; // 90 to -90
    return (lat, lon);
  }

  /// Converts normalized Web Mercator coordinates to lat/lon.
  /// 
  /// The flat map uses Web Mercator projection where:
  /// - x: 0-1 maps to -180° to 180° longitude
  /// - y: 0-1 maps to ~85° to ~-85° latitude (non-linear)
  static (double, double) normalizedMercatorToLatLon(double nx, double ny) {
    final lon = (nx - 0.5) * 360.0;

    // Inverse Mercator projection for latitude
    // y = 0.5 - (1/(2π)) * ln(tan(π/4 + lat/2))
    // Solving for lat: lat = 2 * atan(exp((0.5 - y) * 2π)) - π/2
    final mercatorY = (0.5 - ny) * 2 * math.pi;
    final lat = 2 * math.atan(math.exp(mercatorY)) - math.pi / 2;
    final latDeg = lat * 180.0 / math.pi;

    return (latDeg.clamp(-85.0, 85.0), lon);
  }

  /// Checks if a polygon (defined by a list of lat/lon points) is mostly visible.
  /// 
  /// Returns true if at least one point is on the front side of the globe.
  bool isPolygonVisible(List<(double, double)> points) {
    for (final (lat, lon) in points) {
      final (x, y, z) = latLonToCartesian(lat, lon);
      final (_, _, rz) = applyRotation(x, y, z);
      if (rz >= 0) {
        return true;
      }
    }
    return false;
  }

  /// Inverse projection: converts screen coordinates to lat/lon.
  /// 
  /// Returns null if the point is outside the visible globe.
  (double, double)? screenToLatLon(Offset screenPoint, Offset center, double radius) {
    // Convert screen coordinates to normalized sphere coordinates
    // Note: x is negated to match the projection (viewing from outside)
    final dx = -(screenPoint.dx - center.dx) / (radius * scale);
    final dy = -(screenPoint.dy - center.dy) / (radius * scale);

    // Check if point is within the visible circle
    final distSq = dx * dx + dy * dy;
    if (distSq > 1.0) {
      return null;
    }

    // Calculate z from x and y (on unit sphere: x² + y² + z² = 1)
    // Since we're looking at the front of the sphere, z is positive
    final rz = math.sqrt(1.0 - distSq);

    // Reverse the rotation to get original lat/lon
    final (x, y, z) = _inverseRotation(dx, dy, rz);

    // Convert Cartesian to lat/lon
    final lat = math.asin(y.clamp(-1.0, 1.0)) * 180.0 / math.pi;
    final lon = math.atan2(z, x) * 180.0 / math.pi;

    return (lat, lon);
  }

  /// Inverse of applyRotation
  (double, double, double) _inverseRotation(double x, double y, double z) {
    // Inverse of X rotation
    final cosX = math.cos(-rotationX);
    final sinX = math.sin(-rotationX);
    final y1 = y * cosX - z * sinX;
    final z1 = y * sinX + z * cosX;
    final x1 = x;

    // Inverse of Y rotation
    final cosY = math.cos(-rotationY);
    final sinY = math.sin(-rotationY);
    final x2 = x1 * cosY - z1 * sinY;
    final z2 = x1 * sinY + z1 * cosY;
    final y2 = y1;

    return (x2, y2, z2);
  }
}

