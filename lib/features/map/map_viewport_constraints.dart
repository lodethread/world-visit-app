import 'dart:math' as math;
import 'dart:ui';

/// Computes cover scale and translation constraints for the flat Web Mercator map.
/// The canvas is 3x wide to allow seamless horizontal scrolling across the date line.
class MapViewportConstraints {
  const MapViewportConstraints({required this.worldSize});

  final double worldSize;
  
  /// Total canvas width (3 copies of the world)
  double get canvasWidth => worldSize * 3;

  double coverScale(Size viewport) {
    if (viewport.isEmpty) {
      return 1.0;
    }
    // Scale based on single world size, not the full canvas
    // Ensure the map always covers the viewport (no empty space)
    final scaleX = viewport.width / worldSize;
    final scaleY = viewport.height / worldSize;
    return math.max(scaleX, scaleY);
  }

  MapViewportTransform clamp({
    required Size viewport,
    required double scale,
    required Offset translation,
  }) {
    final minScale = coverScale(viewport);
    final clampedScale = math.max(scale, minScale);
    final Offset clampedTranslation = _clampTranslation(
      viewport: viewport,
      scale: clampedScale,
      translation: translation,
    );
    return MapViewportTransform(
      scale: clampedScale,
      translation: clampedTranslation,
    );
  }

  /// Returns a translation that centers the middle world (the second of three copies)
  Offset centeredTranslation({required Size viewport, required double scale}) {
    final singleWorldWidth = worldSize * scale;
    final worldHeight = worldSize * scale;
    // Center horizontally on the middle world (offset by one world width)
    final tx = (viewport.width - singleWorldWidth) / 2 - singleWorldWidth;
    final ty = (viewport.height - worldHeight) / 2;
    
    final (minTx, maxTx) = _txBounds(viewport, scale);
    return Offset(
      tx.clamp(minTx, maxTx),
      ty.clamp(viewport.height - worldHeight, 0.0),
    );
  }

  /// Calculate horizontal translation bounds
  /// Returns (minTx, maxTx) - simply stops at the boundary, no bouncing
  (double, double) _txBounds(Size viewport, double scale) {
    final totalWidth = canvasWidth * scale;
    final singleWorldWidth = worldSize * scale;
    
    // Horizontal scrolling range across the 3 worlds
    // User can scroll to see any of the 3 worlds, but can't go past the edges
    // This allows seamless wrapping: scroll right to see left world, scroll left to see right world
    
    // Maximum: can't scroll so the right edge of the 3rd world goes past the right edge of viewport
    // When tx = 0, the left edge of world 1 is at the left edge of viewport
    final maxTx = 0.0;
    
    // Minimum: can't scroll so the left edge of the 1st world goes past the left edge of viewport
    // When tx = viewport.width - totalWidth, the right edge of world 3 is at the right edge of viewport
    final minTx = viewport.width - totalWidth;
    
    // If viewport is wider than the canvas (shouldn't happen with coverScale), center it
    if (minTx > maxTx) {
      return (minTx, minTx); // Just stop at the boundary, don't bounce
    }
    
    return (minTx, maxTx);
  }

  Offset _clampTranslation({
    required Size viewport,
    required double scale,
    required Offset translation,
  }) {
    final worldHeight = worldSize * scale;
    
    // Horizontal bounds - simply clamp, no special behavior
    final (minTx, maxTx) = _txBounds(viewport, scale);
    
    // Vertical: standard constraint - no empty space above or below
    final minTy = viewport.height - worldHeight;
    
    return Offset(
      translation.dx.clamp(minTx, maxTx),
      translation.dy.clamp(minTy, 0.0),
    );
  }
}

class MapViewportTransform {
  const MapViewportTransform({required this.scale, required this.translation});

  final double scale;
  final Offset translation;
}
