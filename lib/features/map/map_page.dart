import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';
import 'package:world_visit_app/features/map/lod_resolver.dart';
import 'package:world_visit_app/features/map/map_viewport_constraints.dart';
import 'package:world_visit_app/features/map/widgets/globe_under_construction.dart';
import 'package:world_visit_app/features/map/widgets/map_gesture_layer.dart';
import 'package:world_visit_app/features/map/widgets/map_legend_overlay.dart';
import 'package:world_visit_app/features/map/widgets/map_selection_sheet.dart';
import 'package:world_visit_app/features/place/ui/place_detail_page.dart';
import 'package:world_visit_app/features/visit/ui/visit_editor_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const double _worldSize = 4096.0;
  bool _isGlobe = false;
  bool _loading = true;
  final FlatMapLoader _mapLoader = FlatMapLoader();
  final TransformationController _transformationController =
      TransformationController();
  final WebMercatorProjection _projection = const WebMercatorProjection();
  final MapViewportConstraints _viewportConstraints =
      const MapViewportConstraints(worldSize: _worldSize);
  final MapLodResolver _lodResolver = const MapLodResolver();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  MapLod _lod = MapLod.coarse110m;
  MapLod _desiredLod = MapLod.coarse110m;
  final Map<String, _PlaceLabel> _labels = {};
  final Map<String, int> _levels = {};
  final Map<String, int> _visitCounts = {};
  final Map<String, double> _drawOrders = {};
  Map<String, GeoBounds> _geometryBounds = const <String, GeoBounds>{};
  Map<String, String> _geometryToPlace = const <String, String>{};
  FlatMapDataset? _dataset110m;
  FlatMapDataset? _dataset50m;
  FlatMapDataset? _activeDataset;
  Future<FlatMapDataset>? _loadingFineDataset;
  int _totalScore = 0;
  Size? _viewportSize;
  double? _minScale;
  bool _isApplyingViewportTransform = false;
  Database? _db;
  VisitRepository? _visitRepository;
  TagRepository? _tagRepository;
  MapSelectionSheetData? _selectionData;
  int _debugCandidateCount = 0;
  int _debugParsedFeatures = 0;
  int _debugDrawnPolygons = 0;

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
    final dataset110m = _dataset110m ?? await _mapLoader.loadCountries110m();
    final db = _db ?? await AppDatabase().open();
    _db ??= db;
    _visitRepository ??= VisitRepository(db);
    _tagRepository ??= TagRepository(db);
    final placeRows = await db.query('place');
    final statsRows = await db.query('place_stats');
    final geometryToPlace = <String, String>{};
    final labels = <String, _PlaceLabel>{};
    for (final row in placeRows) {
      final placeCode = row['place_code']?.toString();
      if (placeCode == null) {
        continue;
      }
      labels[placeCode] = _PlaceLabel(
        nameJa: row['name_ja'] as String,
        nameEn: row['name_en'] as String,
      );
      final geometryId = row['geometry_id']?.toString();
      if (geometryId == null || geometryId.isEmpty) {
        continue;
      }
      geometryToPlace[geometryId] = placeCode;
    }
    final visitCounts = <String, int>{};
    int total = 0;
    final levels = <String, int>{};
    for (final row in statsRows) {
      final level = (row['max_level'] as int?) ?? 0;
      final placeCode = row['place_code'] as String;
      levels[placeCode] = level;
      visitCounts[placeCode] = (row['visit_count'] as int?) ?? 0;
      total += level;
    }
    final selectedPlace = _selectionData?.placeCode;
    setState(() {
      _dataset110m ??= dataset110m;
      _labels
        ..clear()
        ..addAll(labels);
      _levels
        ..clear()
        ..addAll(levels);
      _visitCounts
        ..clear()
        ..addAll(visitCounts);
      _geometryToPlace = geometryToPlace;
      _totalScore = total;
      _loading = false;
      _drawOrders.clear();
      _updateDrawOrdersFromDataset(_dataset110m!);
      final fine = _dataset50m;
      if (fine != null) {
        _updateDrawOrdersFromDataset(fine);
      }
      _refreshActiveDatasetLocked();
    });
    if (_desiredLod == MapLod.fine50m) {
      unawaited(_ensureFineDatasetLoaded());
    }
    if (selectedPlace != null && mounted) {
      await _selectPlace(selectedPlace, animateSheet: false);
    }
  }

  void _refreshActiveDatasetLocked() {
    if (_lod == MapLod.fine50m && _dataset50m == null) {
      _lod = MapLod.coarse110m;
    }
    final dataset = _lod == MapLod.fine50m ? _dataset50m : _dataset110m;
    if (dataset == null) {
      return;
    }
    _setActiveDataset(dataset);
  }

  void _setActiveDataset(FlatMapDataset dataset) {
    _activeDataset = dataset;
    _geometryBounds = dataset.boundsByGeometry;
    if (!kReleaseMode) {
      _debugParsedFeatures = dataset.geometries.length;
      _debugDrawnPolygons = dataset.polygons.length;
    }
  }

  void _activateLod(MapLod lod) {
    final dataset = lod == MapLod.fine50m ? _dataset50m : _dataset110m;
    if (dataset == null) {
      return;
    }
    setState(() {
      _lod = lod;
      _setActiveDataset(dataset);
    });
  }

  double? _estimateLonSpan() {
    final viewport = _viewportSize;
    if (viewport == null || viewport.isEmpty) {
      return null;
    }
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale <= 0) {
      return null;
    }
    final visibleFraction = (viewport.width / (_worldSize * scale)).clamp(
      0.0,
      1.0,
    );
    return 360.0 * visibleFraction;
  }

  Future<void> _ensureFineDatasetLoaded() async {
    if (_dataset50m != null || _loadingFineDataset != null) {
      return;
    }
    final future = _mapLoader.loadCountries50m();
    _loadingFineDataset = future;
    try {
      final dataset = await future;
      if (!mounted) {
        return;
      }
      setState(() {
        _dataset50m = dataset;
        _updateDrawOrdersFromDataset(dataset);
      });
      if (_desiredLod == MapLod.fine50m) {
        _activateLod(MapLod.fine50m);
      }
    } finally {
      if (identical(_loadingFineDataset, future)) {
        _loadingFineDataset = null;
      }
    }
  }

  void _updateDrawOrdersFromDataset(FlatMapDataset dataset) {
    for (final polygon in dataset.polygons) {
      final existing = _drawOrders[polygon.geometryId];
      if (existing == null || polygon.drawOrder > existing) {
        _drawOrders[polygon.geometryId] = polygon.drawOrder;
      }
    }
  }

  void _updateViewportSize(Size size) {
    if (size.isEmpty) {
      return;
    }
    final coverScale = _viewportConstraints.coverScale(size);
    final previousScale = _minScale;
    _viewportSize = size;
    _minScale = coverScale;
    if (previousScale == null || (previousScale - coverScale).abs() > 1e-6) {
      _applyInitialTransform();
    } else {
      _enforceViewportConstraints();
    }
  }

  void _applyInitialTransform() {
    final viewport = _viewportSize;
    final minScale = _minScale;
    if (viewport == null || minScale == null) {
      return;
    }
    final translation = _viewportConstraints.centeredTranslation(
      viewport: viewport,
      scale: minScale,
    );
    _applyTransform(
      MapViewportTransform(scale: minScale, translation: translation),
    );
  }

  bool _enforceViewportConstraints() {
    final viewport = _viewportSize;
    if (viewport == null) {
      return false;
    }
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = Offset(matrix.storage[12], matrix.storage[13]);
    final target = _viewportConstraints.clamp(
      viewport: viewport,
      scale: scale,
      translation: translation,
    );
    if (_nearlyEqual(target.scale, scale) &&
        _offsetNear(target.translation, translation)) {
      return false;
    }
    _applyTransform(target);
    return true;
  }

  void _applyTransform(MapViewportTransform transform) {
    _isApplyingViewportTransform = true;
    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, transform.scale);
    matrix.setEntry(1, 1, transform.scale);
    matrix.setEntry(2, 2, 1.0);
    matrix.setEntry(3, 3, 1.0);
    matrix.setTranslationRaw(
      transform.translation.dx,
      transform.translation.dy,
      0,
    );
    _transformationController.value = matrix;
    _isApplyingViewportTransform = false;
  }

  void _handleViewportChanged() {
    if (_isApplyingViewportTransform) {
      return;
    }
    _enforceViewportConstraints();
    _updateLodForCurrentView();
  }

  void _updateLodForCurrentView() {
    if (_dataset110m == null) {
      return;
    }
    final lonSpan = _estimateLonSpan();
    if (lonSpan == null) {
      return;
    }
    final nextLod = _lodResolver.resolve(lonSpan, _lod);
    if (nextLod == _lod) {
      return;
    }
    _desiredLod = nextLod;
    if (nextLod == MapLod.fine50m && _dataset50m == null) {
      _ensureFineDatasetLoaded();
      return;
    }
    _activateLod(nextLod);
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
    final dataset = _activeDataset;
    if (dataset == null) {
      _updateCandidateDebug(0);
      return const <_PlaceCandidate>[];
    }
    final normalized = _normalizedFromLocal(position);
    if (normalized == null) {
      _updateCandidateDebug(0);
      return const <_PlaceCandidate>[];
    }
    final geoPoint = _projection.unproject(normalized);
    final geometryIds = <String>{...dataset.spatialIndex.query(normalized)};
    if (geometryIds.isEmpty) {
      _geometryBounds.forEach((geometryId, bounds) {
        if (bounds.contains(geoPoint.dx, geoPoint.dy)) {
          geometryIds.add(geometryId);
        }
      });
    }
    if (geometryIds.isEmpty) {
      _updateCandidateDebug(0);
      return const <_PlaceCandidate>[];
    }
    final Map<String, _PlaceCandidate> aggregated = {};
    for (final geometryId in geometryIds) {
      final placeCode = _geometryToPlace[geometryId];
      if (placeCode == null) {
        continue;
      }
      final geometry = dataset.geometries[geometryId];
      if (geometry == null) {
        continue;
      }
      bool hit = false;
      for (final polygon in geometry.polygons) {
        if (polygon.containsPoint(normalized)) {
          hit = true;
          break;
        }
      }
      if (!hit) {
        continue;
      }
      final drawOrder = _drawOrders[geometryId] ?? geometry.drawOrder;
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
    _updateCandidateDebug(candidates.length);
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

  Offset? _normalizedFromLocal(Offset position) {
    final scenePoint = _transformationController.toScene(position);
    final normalized = Offset(
      scenePoint.dx / _worldSize,
      scenePoint.dy / _worldSize,
    );
    if (normalized.dx.isNaN ||
        normalized.dy.isNaN ||
        normalized.dx < 0 ||
        normalized.dx > 1 ||
        normalized.dy < 0 ||
        normalized.dy > 1) {
      return null;
    }
    return normalized;
  }

  void _updateCandidateDebug(int count) {
    if (kReleaseMode || !mounted || _debugCandidateCount == count) {
      _debugCandidateCount = count;
      return;
    }
    setState(() {
      _debugCandidateCount = count;
    });
  }

  bool _nearlyEqual(double a, double b, [double epsilon = 1e-6]) {
    return (a - b).abs() < epsilon;
  }

  bool _offsetNear(Offset a, Offset b, [double epsilon = 0.5]) {
    return (a.dx - b.dx).abs() < epsilon && (a.dy - b.dy).abs() < epsilon;
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

  List<MapLegendEntry> get _legendEntries {
    return [
      MapLegendEntry(
        levelLabel: '0 未踏',
        description: '未踏',
        color: _colorForLevel(0),
      ),
      MapLegendEntry(
        levelLabel: '1 乗継（空港のみ）',
        description: '乗継（空港のみ）',
        color: _colorForLevel(1),
      ),
      MapLegendEntry(
        levelLabel: '2 乗継（少し観光）',
        description: '乗継（少し観光）',
        color: _colorForLevel(2),
      ),
      MapLegendEntry(
        levelLabel: '3 訪問（宿泊なし）',
        description: '訪問（宿泊なし）',
        color: _colorForLevel(3),
      ),
      MapLegendEntry(
        levelLabel: '4 観光（宿泊あり）',
        description: '観光（宿泊あり）',
        color: _colorForLevel(4),
      ),
      MapLegendEntry(
        levelLabel: '5 居住',
        description: '居住',
        color: _colorForLevel(5),
      ),
    ];
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
    final dataset = _activeDataset;
    if (dataset == null || dataset.polygons.isEmpty) {
      return const Center(child: Text('地図データがありません'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _updateViewportSize(size);
        final painter = _FlatMapPainter(
          polygons: dataset.polygons,
          levels: _levels,
          colorResolver: _colorForLevel,
          geometryToPlace: _geometryToPlace,
          selectedPlaceCode: _selectionData?.placeCode,
        );
        final canvas = SizedBox(
          width: _worldSize,
          height: _worldSize,
          child: CustomPaint(painter: painter),
        );
        final viewer = InteractiveViewer(
          transformationController: _transformationController,
          minScale: _minScale ?? 1.0,
          maxScale: 20.0,
          panEnabled: true,
          scaleEnabled: true,
          boundaryMargin: EdgeInsets.zero,
          clipBehavior: Clip.none,
          child: canvas,
        );
        return MapGestureLayer(
          enabled: !_loading && _activeDataset != null,
          onTap: _clearSelection,
          onLongPress: (position) => _handleLongPress(position),
          child: SizedBox.expand(child: viewer),
        );
      },
    );
  }

  Widget _buildGlobePlaceholder() {
    return GlobeUnderConstruction(
      onExit: () => setState(() => _isGlobe = false),
    );
  }

  Widget _buildSelectionSheet() {
    final data = _selectionData;
    if (data == null) {
      return const SizedBox.shrink();
    }
    return MapSelectionSheet(
      key: ValueKey(data.placeCode),
      controller: _sheetController,
      data: data,
      onAddVisit: _addVisitFromSheet,
      onDuplicateVisit: _duplicateVisitFromSheet,
      onOpenDetail: _openDetailFromSheet,
      onClose: _clearSelection,
    );
  }

  Widget _buildDebugOverlay() {
    if (kReleaseMode) {
      return const SizedBox.shrink();
    }
    final lodLabel = _lod == MapLod.coarse110m ? '110m' : '50m';
    return Positioned(
      bottom: 16,
      right: 16,
      child: IgnorePointer(
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.2,
              ),
              child: Text(
                'LOD: $lodLabel\n'
                'Parsed: $_debugParsedFeatures\n'
                'Polygons: $_debugDrawnPolygons\n'
                'Candidates: $_debugCandidateCount',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectionData == null && !_isGlobe,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_selectionData != null) {
          _clearSelection();
          return;
        }
        if (_isGlobe) {
          setState(() => _isGlobe = false);
        }
      },
      child: Scaffold(
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _isGlobe ? _buildGlobePlaceholder() : _buildFlatMap(),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
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
            ),
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(child: MapLegendOverlay(entries: _legendEntries)),
            ),
            if (!kReleaseMode) _buildDebugOverlay(),
            if (_selectionData != null) _buildSelectionSheet(),
          ],
        ),
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
    required this.selectedPlaceCode,
  });

  final List<MapPolygon> polygons;
  final Map<String, int> levels;
  final Color Function(int) colorResolver;
  final Map<String, String> geometryToPlace;
  final String? selectedPlaceCode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final scaleX = size.width;
    final scaleY = size.height;
    final strokeScale = (scaleX + scaleY) / 2.0;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = strokeScale == 0 ? 0 : 1.0 / strokeScale;
    final highlightStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = strokeScale == 0 ? 0 : 2.5 / strokeScale;

    canvas.save();
    canvas.scale(scaleX, scaleY);
    for (final polygon in polygons) {
      final placeCode = geometryToPlace[polygon.geometryId];
      if (placeCode == null) {
        continue;
      }
      final level = levels[placeCode] ?? 0;
      final isSelected = placeCode == selectedPlaceCode;
      final baseColor = colorResolver(level);
      fillPaint.color = isSelected
          ? baseColor
          : baseColor.withValues(alpha: 0.85);
      final path = polygon.path;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, isSelected ? highlightStrokePaint : strokePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlatMapPainter oldDelegate) {
    return oldDelegate.polygons != polygons ||
        oldDelegate.levels != levels ||
        oldDelegate.geometryToPlace != geometryToPlace ||
        oldDelegate.selectedPlaceCode != selectedPlaceCode;
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
