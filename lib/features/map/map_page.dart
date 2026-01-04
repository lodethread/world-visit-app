import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/place/ui/place_detail_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool _isGlobe = false;
  bool _loading = true;
  final List<MapPolygon> _polygons = [];
  final Map<String, _PlaceLabel> _labels = {};
  final Map<String, int> _levels = {};
  final Map<String, double> _drawOrders = {};
  Map<String, String> _geometryToPlace = const {};
  int _totalScore = 0;
  Database? _db;

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    final loader = FlatMapLoader();
    final polygons = await loader.load();
    final sortedPolygons = [...polygons]
      ..sort((a, b) => a.drawOrder.compareTo(b.drawOrder));
    final drawOrders = <String, double>{};
    for (final polygon in sortedPolygons) {
      final existing = drawOrders[polygon.geometryId];
      if (existing == null || polygon.drawOrder > existing) {
        drawOrders[polygon.geometryId] = polygon.drawOrder;
      }
    }
    final db = _db ?? await AppDatabase().open();
    _db ??= db;
    final placeRows = await db.query('place');
    final statsRows = await db.query('place_stats');
    final geometryToPlace = <String, String>{};
    _labels
      ..clear()
      ..addEntries(
        placeRows.map(
          (row) => MapEntry(
            row['place_code'] as String,
            _PlaceLabel(
              nameJa: row['name_ja'] as String,
              nameEn: row['name_en'] as String,
            ),
          ),
        ),
      );
    for (final row in placeRows) {
      final geometryId = row['geometry_id']?.toString();
      final placeCode = row['place_code']?.toString();
      if (geometryId == null || geometryId.isEmpty || placeCode == null) {
        continue;
      }
      geometryToPlace[geometryId] = placeCode;
    }
    _levels.clear();
    int total = 0;
    for (final row in statsRows) {
      final level = (row['max_level'] as int?) ?? 0;
      _levels[row['place_code'] as String] = level;
      total += level;
    }
    setState(() {
      _polygons
        ..clear()
        ..addAll(sortedPolygons);
      _drawOrders
        ..clear()
        ..addAll(drawOrders);
      _geometryToPlace = geometryToPlace;
      _totalScore = total;
      _loading = false;
    });
  }

  Future<void> _handleLongPress(Offset position, Size size) async {
    final candidates = _hitTestCandidates(position, size);
    if (candidates.isEmpty) {
      return;
    }
    final selectedCode = candidates.length == 1
        ? candidates.first.placeCode
        : await _showCandidateSheet(candidates);
    if (selectedCode == null ||
        !_labels.containsKey(selectedCode) ||
        !mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaceDetailPage(placeCode: selectedCode),
      ),
    );
    if (mounted) {
      setState(() => _loading = true);
      await _loadData();
    }
  }

  List<_PlaceCandidate> _hitTestCandidates(Offset position, Size size) {
    if (_polygons.isEmpty || size.width <= 0 || size.height <= 0) {
      return const <_PlaceCandidate>[];
    }
    final normalized = Offset(
      (position.dx / size.width).clamp(0.0, 1.0),
      (position.dy / size.height).clamp(0.0, 1.0),
    );
    final Map<String, _PlaceCandidate> aggregated = {};
    for (final polygon in _polygons) {
      if (!polygon.containsPoint(normalized)) {
        continue;
      }
      final placeCode = _geometryToPlace[polygon.geometryId];
      if (placeCode == null) {
        continue;
      }
      final drawOrder = _drawOrders[polygon.geometryId] ?? polygon.drawOrder;
      final displayName = _displayName(placeCode);
      final existing = aggregated[placeCode];
      if (existing == null || drawOrder > existing.drawOrder) {
        aggregated[placeCode] = _PlaceCandidate(
          placeCode: placeCode,
          drawOrder: drawOrder,
          displayName: displayName,
        );
      }
    }
    final candidates = aggregated.values.toList()
      ..sort((a, b) {
        final drawComparison = b.drawOrder.compareTo(a.drawOrder);
        if (drawComparison != 0) {
          return drawComparison;
        }
        return a.displayName.compareTo(b.displayName);
      });
    return candidates;
  }

  Future<String?> _showCandidateSheet(List<_PlaceCandidate> candidates) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('場所を選択してください')),
                ),
                ...candidates.map(
                  (candidate) => ListTile(
                    title: Text(candidate.displayName),
                    onTap: () =>
                        Navigator.of(context).pop<String>(candidate.placeCode),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _displayName(String placeCode) {
    final label = _labels[placeCode];
    if (label == null) {
      return placeCode;
    }
    final locale = Localizations.maybeLocaleOf(context);
    if (locale?.languageCode == 'en') {
      return label.nameEn;
    }
    return label.nameJa;
  }

  Color _colorForLevel(int level) {
    switch (level) {
      case 0:
        return const Color(0xFF1b263b);
      case 1:
        return const Color(0xFF3a86ff);
      case 2:
        return const Color(0xFF00b4d8);
      case 3:
        return const Color(0xFF80ed99);
      case 4:
        return const Color(0xFFffd166);
      case 5:
      default:
        return const Color(0xFFef476f);
    }
  }

  Widget _buildFlatMap() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_polygons.isEmpty) {
      return const Center(child: Text('地図データがありません'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onLongPressStart: (details) =>
              _handleLongPress(details.localPosition, size),
          child: CustomPaint(
            size: size,
            painter: _FlatMapPainter(
              polygons: _polygons,
              levels: _levels,
              colorResolver: _colorForLevel,
              geometryToPlace: _geometryToPlace,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlobePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.public, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Globe map is under construction.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _isGlobe ? _buildGlobePlaceholder() : _buildFlatMap(),
          ),
          Positioned(
            top: 40,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '経国値: $_totalScore',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _isGlobe = false),
                        child: Text(
                          'Flat',
                          style: TextStyle(
                            color: _isGlobe
                                ? Colors.white70
                                : Colors.amberAccent,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _isGlobe = true),
                        child: Text(
                          'Globe',
                          style: TextStyle(
                            color: _isGlobe
                                ? Colors.amberAccent
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlatMapPainter extends CustomPainter {
  _FlatMapPainter({
    required this.polygons,
    required this.levels,
    required this.colorResolver,
    required this.geometryToPlace,
  });

  final List<MapPolygon> polygons;
  final Map<String, int> levels;
  final Color Function(int) colorResolver;
  final Map<String, String> geometryToPlace;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;

    for (final polygon in polygons) {
      final placeCode = geometryToPlace[polygon.geometryId];
      if (placeCode == null) {
        continue;
      }
      final level = levels[placeCode] ?? 0;
      fillPaint.color = colorResolver(level);
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in polygon.rings) {
        if (ring.isEmpty) continue;
        final first = _scaleOffset(ring.first, size);
        path.moveTo(first.dx, first.dy);
        for (int k = 1; k < ring.length; k++) {
          final pt = _scaleOffset(ring[k], size);
          path.lineTo(pt.dx, pt.dy);
        }
        path.close();
      }
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  Offset _scaleOffset(Offset offset, Size size) {
    return Offset(offset.dx * size.width, offset.dy * size.height);
  }

  @override
  bool shouldRepaint(covariant _FlatMapPainter oldDelegate) {
    return oldDelegate.polygons != polygons ||
        oldDelegate.levels != levels ||
        oldDelegate.geometryToPlace != geometryToPlace;
  }
}

class _PlaceLabel {
  const _PlaceLabel({required this.nameJa, required this.nameEn});
  final String nameJa;
  final String nameEn;
}

class _PlaceCandidate {
  const _PlaceCandidate({
    required this.placeCode,
    required this.drawOrder,
    required this.displayName,
  });

  final String placeCode;
  final double drawOrder;
  final String displayName;
}
