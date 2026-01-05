import 'dart:math' as math;
import 'dart:ui';

/// Computes cover scale and translation constraints for the flat Web Mercator map.
class MapViewportConstraints {
  const MapViewportConstraints({required this.worldSize});

  final double worldSize;

  double coverScale(Size viewport) {
    if (viewport.isEmpty) {
      return 1.0;
    }
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

  Offset centeredTranslation({required Size viewport, required double scale}) {
    final worldWidth = worldSize * scale;
    final worldHeight = worldSize * scale;
    final tx = (viewport.width - worldWidth) / 2;
    final ty = (viewport.height - worldHeight) / 2;
    return Offset(
      tx.clamp(viewport.width - worldWidth, 0.0),
      ty.clamp(viewport.height - worldHeight, 0.0),
    );
  }

  Offset _clampTranslation({
    required Size viewport,
    required double scale,
    required Offset translation,
  }) {
    final worldWidth = worldSize * scale;
    final worldHeight = worldSize * scale;
    final minTx = viewport.width - worldWidth;
    final minTy = viewport.height - worldHeight;
    return Offset(
      translation.dx.clamp(minTx, 0.0),
      translation.dy.clamp(minTy, 0.0),
    );
  }
}

class MapViewportTransform {
  const MapViewportTransform({required this.scale, required this.translation});

  final double scale;
  final Offset translation;
}
