import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';
import 'package:world_visit_app/features/map/lod_resolver.dart';
import 'package:world_visit_app/features/map/widgets/map_selection_sheet.dart';
import 'package:world_visit_app/features/place/ui/place_detail_page.dart';
import 'package:world_visit_app/features/visit/ui/visit_editor_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool _isGlobe = false;
  bool _loading = true;
  final TransformationController _transformationController =
      TransformationController();
  final WebMercatorProjection _projection = const WebMercatorProjection();
  final MapLodResolver _lodResolver = const MapLodResolver();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  MapLod _lod = MapLod.coarse110m;
  final List<MapPolygon> _polygons = [];
  final Map<String, _PlaceLabel> _labels = {};
  final Map<String, int> _levels = {};
  final Map<String, int> _visitCounts = {};
  final Map<String, double> _drawOrders = {};
  Map<String, GeoBounds> _geometryBounds = const <String, GeoBounds>{};
  Map<String, String> _geometryToPlace = const <String, String>{};
  FlatMapDataset? _dataset110m;
  FlatMapDataset? _dataset50m;
  FlatMapDataset? _activeDataset;
  int _totalScore = 0;
  Size? _viewportSize;
  Database? _db;
  VisitRepository? _visitRepository;
  TagRepository? _tagRepository;
  MapSelectionSheetData? _selectionData;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handleViewportChanged);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleViewportChanged);
    _transformationController.dispose();
    _sheetController.dispose();
    _db?.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    final loader = FlatMapLoader();
    final datasets = await Future.wait([
      loader.loadCountries110m(),
      loader.loadCountries50m(),
    ]);
    final dataset110m = datasets[0];
    final dataset50m = datasets[1];
    final drawOrders = <String, double>{};
    for (final polygon in dataset50m.polygons) {
      final existing = drawOrders[polygon.geometryId];
      if (existing == null || polygon.drawOrder > existing) {
        drawOrders[polygon.geometryId] = polygon.drawOrder;
      }
    }
    final db = _db ?? await AppDatabase().open();
    _db ??= db;
    _visitRepository ??= VisitRepository(db);
    _tagRepository ??= TagRepository(db);
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
    final visitCounts = <String, int>{};
    int total = 0;
    for (final row in statsRows) {
      final level = (row['max_level'] as int?) ?? 0;
      final placeCode = row['place_code'] as String;
      _levels[placeCode] = level;
      visitCounts[placeCode] = (row['visit_count'] as int?) ?? 0;
      total += level;
    }
    final selectedPlace = _selectionData?.placeCode;
    setState(() {
      _dataset110m = dataset110m;
      _dataset50m = dataset50m;
      _applyDataset(_lod);
      _drawOrders
        ..clear()
        ..addAll(drawOrders);
      _geometryToPlace = geometryToPlace;
      _visitCounts
        ..clear()
        ..addAll(visitCounts);
      _totalScore = total;
      _loading = false;
    });
    if (selectedPlace != null && mounted) {
      await _selectPlace(selectedPlace, animateSheet: false);
    }
  }

  void _applyDataset(MapLod lod) {
    final dataset = lod == MapLod.coarse110m ? _dataset110m : _dataset50m;
    if (dataset == null) {
      return;
    }
    _activeDataset = dataset;
    _polygons
      ..clear()
      ..addAll(dataset.polygons);
    _geometryBounds = dataset.boundsByGeometry;
  }

  void _handleViewportChanged() {
    if (_dataset110m == null || _dataset50m == null) {
      return;
    }
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale <= 0) {
      return;
    }
    final lonSpan = 360.0 / scale;
    final nextLod = _lodResolver.resolve(lonSpan, _lod);
    if (nextLod == _lod) {
      return;
    }
    setState(() {
      _lod = nextLod;
      _applyDataset(nextLod);
    });
  }

  Future<void> _handleLongPress(Offset position) async {
    final candidates = _hitTestCandidates(position);
    if (candidates.isEmpty) {
      return;
    }
    final selectedCode = candidates.length == 1
        ? candidates.first.placeCode
        : await _showCandidateSheet(candidates);
    if (selectedCode == null || !_labels.containsKey(selectedCode)) {
      return;
    }
    await _selectPlace(selectedCode);
  }

  List<_PlaceCandidate> _hitTestCandidates(Offset position) {
    final size = _viewportSize;
    final dataset = _activeDataset;
    if (size == null || dataset == null || _polygons.isEmpty) {
      return const <_PlaceCandidate>[];
    }
    final scenePoint = _transformationController.toScene(position);
    final normalized = Offset(
      scenePoint.dx / size.width,
      scenePoint.dy / size.height,
    );
    if (normalized.dx.isNaN ||
        normalized.dy.isNaN ||
        normalized.dx < 0 ||
        normalized.dx > 1 ||
        normalized.dy < 0 ||
        normalized.dy > 1) {
      return const <_PlaceCandidate>[];
    }
    final geoPoint = _projection.unproject(normalized);
    final geometryIds = <String>[];
    _geometryBounds.forEach((geometryId, bounds) {
      if (bounds.contains(geoPoint.dx, geoPoint.dy)) {
        geometryIds.add(geometryId);
      }
    });
    if (geometryIds.isEmpty) {
      return const <_PlaceCandidate>[];
    }
    final Map<String, _PlaceCandidate> aggregated = {};
    for (final geometryId in geometryIds) {
      final placeCode = _geometryToPlace[geometryId];
      if (placeCode == null) {
        continue;
      }
      final polygons = dataset.geometries[geometryId]?.polygons ?? const [];
      bool hit = false;
      for (final polygon in polygons) {
        if (polygon.containsPoint(normalized)) {
          hit = true;
          break;
        }
      }
      if (!hit) {
        continue;
      }
      final drawOrder =
          _drawOrders[geometryId] ??
          dataset.geometries[geometryId]?.drawOrder ??
          0;
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

  Future<void> _selectPlace(
    String placeCode, {
    bool animateSheet = true,
  }) async {
    await _ensureRepositories();
    final latestVisit = await _visitRepository?.latestVisitForPlace(placeCode);
    if (!mounted) return;
    final level = _levels[placeCode] ?? 0;
    final details = MapSelectionSheetData(
      placeCode: placeCode,
      displayName: _displayName(placeCode),
      level: level,
      levelLabel: _levelLabel(level),
      levelColor: _colorForLevel(level),
      visitCount: _visitCounts[placeCode] ?? 0,
      latestVisit: latestVisit,
    );
    setState(() {
      _selectionData = details;
    });
    if (animateSheet) {
      _expandSheet();
    }
  }

  Future<void> _ensureRepositories() async {
    if (_visitRepository != null && _tagRepository != null) {
      return;
    }
    final db = _db ?? await AppDatabase().open();
    _db ??= db;
    _visitRepository ??= VisitRepository(db);
    _tagRepository ??= TagRepository(db);
  }

  void _expandSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sheetController.isAttached) {
        return;
      }
      unawaited(
        _sheetController.animateTo(
          0.25,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        ),
      );
    });
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

  String _levelLabel(int level) {
    switch (level) {
      case 0:
        return '未踏';
      case 1:
        return '乗継（空港のみ）';
      case 2:
        return '乗継（少し観光）';
      case 3:
        return '訪問（宿泊なし）';
      case 4:
        return '観光（宿泊あり）';
      case 5:
        return '居住';
      default:
        return '未分類';
    }
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

  Future<void> _addVisitFromSheet() async {
    final placeCode = _selectionData?.placeCode;
    if (placeCode == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditorPage(initialPlaceCode: placeCode),
      ),
    );
    if (!mounted || result != true) return;
    setState(() => _loading = true);
    await _loadData();
  }

  Future<void> _duplicateVisitFromSheet() async {
    final placeCode = _selectionData?.placeCode;
    if (placeCode == null) return;
    await _ensureRepositories();
    final repo = _visitRepository;
    if (repo == null) return;
    final latest = await repo.latestVisitForPlace(placeCode);
    if (latest == null) {
      _showMessage('このPlaceのVisitがありません');
      return;
    }
    final tags = await _tagRepository!.listByVisitId(latest.visitId);
    if (!mounted) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditorPage(
          initialPlaceCode: placeCode,
          initialTitle: latest.title,
          initialLevel: latest.level,
          initialNote: latest.note,
          initialTags: tags,
        ),
      ),
    );
    if (!mounted || result != true) return;
    setState(() => _loading = true);
    await _loadData();
  }

  Future<void> _openDetailFromSheet() async {
    final placeCode = _selectionData?.placeCode;
    if (placeCode == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaceDetailPage(placeCode: placeCode)),
    );
    if (!mounted) return;
    setState(() => _loading = true);
    await _loadData();
  }

  void _clearSelection() {
    if (_selectionData == null) {
      return;
    }
    setState(() => _selectionData = null);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        _viewportSize = size;
        final painter = _FlatMapPainter(
          polygons: _polygons,
          levels: _levels,
          colorResolver: _colorForLevel,
          geometryToPlace: _geometryToPlace,
        );
        final canvas = SizedBox(
          width: size.width,
          height: size.height,
          child: CustomPaint(painter: painter),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _clearSelection(),
          onLongPressStart: (details) =>
              _handleLongPress(details.localPosition),
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 12.0,
            panEnabled: true,
            scaleEnabled: true,
            boundaryMargin: const EdgeInsets.all(200),
            clipBehavior: Clip.none,
            child: canvas,
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

  Widget _buildSelectionSheet() {
    final data = _selectionData;
    if (data == null) {
      return const SizedBox.shrink();
    }
    return MapSelectionSheet(
      controller: _sheetController,
      data: data,
      onAddVisit: _addVisitFromSheet,
      onDuplicateVisit: _duplicateVisitFromSheet,
      onOpenDetail: _openDetailFromSheet,
      onClose: _clearSelection,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        clipBehavior: Clip.none,
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
          if (_selectionData != null) _buildSelectionSheet(),
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
