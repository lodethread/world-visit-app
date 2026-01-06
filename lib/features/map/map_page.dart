import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/data/db/tag_repository.dart';
import 'package:world_visit_app/data/db/visit_repository.dart';
import 'package:world_visit_app/features/map/data/flat_map_loader.dart';
import 'package:world_visit_app/features/map/data/map_dataset_guard.dart';
import 'package:world_visit_app/features/map/flat_map_geometry.dart';
import 'package:world_visit_app/features/map/lod_resolver.dart';
import 'package:world_visit_app/features/map/map_viewport_constraints.dart';
import 'package:world_visit_app/features/map/globe/globe_map_widget.dart';
import 'package:world_visit_app/features/map/widgets/globe_under_construction.dart';
import 'package:world_visit_app/features/map/widgets/map_gesture_layer.dart';
import 'package:world_visit_app/features/map/widgets/map_selection_sheet.dart';
import 'package:world_visit_app/features/place/ui/place_detail_page.dart';
import 'package:world_visit_app/features/visit/ui/visit_editor_page.dart';

// #region agent log
void _debugLog(
  String location,
  String message,
  Map<String, dynamic> data,
  String hypothesisId,
) {
  final entry = jsonEncode({
    'location': location,
    'message': message,
    'data': data,
    'hypothesisId': hypothesisId,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'sessionId': 'debug-session',
  });
  debugPrint('[DEBUG] $entry');
}
// #endregion

class MapPage extends StatefulWidget {
  const MapPage({super.key, this.mapLoader, this.openDatabase});

  final FlatMapLoader? mapLoader;
  final Future<Database> Function()? openDatabase;

  @override
  State<MapPage> createState() => MapPageState();
}

sealed class MapRenderState {
  const MapRenderState();
}

class MapRenderLoading extends MapRenderState {
  const MapRenderLoading();
}

class MapRenderReady extends MapRenderState {
  const MapRenderReady();
}

class MapRenderError extends MapRenderState {
  const MapRenderError({required this.message, this.details});

  final String message;
  final String? details;
}

class MapDataException implements Exception {
  const MapDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MapPageState extends State<MapPage> {
  /// Refresh map data from database
  Future<void> refresh() async {
    if (!mounted) return;
    _setLoadingState();
    await _loadData();
  }

  static const double _worldSize = 4096.0;
  static const String _mapLoadErrorMessage = '地図データの読み込みに失敗しました';
  static const bool _kEnableDebugOverlay = false;
  static const String _kAntarcticaPlaceCode = 'AQ';
  static const String _kAntarcticaGeometryId = '010';
  static const double _kAntarcticaNormalizedThreshold = 0.85;
  bool _isGlobe = true; // Default to Globe view
  late final FlatMapLoader _mapLoader;
  late final Future<Database> Function() _openDatabase;
  final TransformationController _transformationController =
      TransformationController();
  final WebMercatorProjection _projection = const WebMercatorProjection();
  final MapViewportConstraints _viewportConstraints =
      const MapViewportConstraints(worldSize: _worldSize);
  final MapLodResolver _lodResolver = const MapLodResolver();
  DraggableScrollableController _sheetController =
      DraggableScrollableController();
  MapLod _lod = MapLod.coarse110m;
  MapLod _desiredLod = MapLod.coarse110m;
  final Map<String, _PlaceLabel> _labels = {};
  final Map<String, int> _levels = {};
  final Map<String, int> _visitCounts = {};
  Map<int, int> _levelCounts = const {};
  final Map<String, double> _drawOrders = {};
  Map<String, GeoBounds> _geometryBounds = const <String, GeoBounds>{};
  Map<String, String> _geometryToPlace = const <String, String>{};
  FlatMapDataset? _dataset110m;
  FlatMapDataset? _dataset50m;
  FlatMapDataset? _activeDataset;
  Future<FlatMapDataset>? _loadingFineDataset;
  MapRenderState _renderState = const MapRenderLoading();
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
  int _debugMappedPolygons = 0;
  int _debugFillCount = 0;
  int _debugOutlineOnlyCount = 0;
  double _debugScale = 1.0;
  Offset _debugTranslation = Offset.zero;
  bool _hasDrawablePolygons = true;
  _MapPaintMetrics _lastPaintMetrics = _MapPaintMetrics.zero;

  @override
  void initState() {
    super.initState();
    _mapLoader = widget.mapLoader ?? FlatMapLoader();
    _openDatabase = widget.openDatabase ?? () => AppDatabase().open();
    _transformationController.addListener(_handleViewportChanged);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleViewportChanged);
    _transformationController.dispose();
    _sheetController.dispose();
    // Note: Do NOT close DB here - it's shared across the app
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final dataset110m = _dataset110m ?? await _mapLoader.loadCountries110m();
      MapDatasetGuard.ensureUsable(dataset110m, label: 'countries_110m');
      final db = _db ?? await _openDatabase();
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
      if (geometryToPlace.isEmpty && kDebugMode) {
        debugPrint(
          'Geometry to place mapping is empty. Rendering outlines only.',
        );
      }
      final visitCounts = <String, int>{};
      int total = 0;
      final levels = <String, int>{};
      final nonZeroLevels = <String, int>{};
      final levelCounts = <int, int>{};
      for (final row in statsRows) {
        final level = (row['max_level'] as int?) ?? 0;
        final placeCode = row['place_code'] as String;
        levels[placeCode] = level;
        visitCounts[placeCode] = (row['visit_count'] as int?) ?? 0;
        total += level;
        if (level > 0) {
          nonZeroLevels[placeCode] = level;
          levelCounts[level] = (levelCounts[level] ?? 0) + 1;
        }
      }
      // #region agent log
      _debugLog(
        'map_page.dart:_loadData:levels',
        'Levels loaded from place_stats',
        {
          'totalScore': total,
          'statsRowsCount': statsRows.length,
          'nonZeroLevelsCount': nonZeroLevels.length,
          'nonZeroLevels': nonZeroLevels.entries
              .take(10)
              .map((e) => '${e.key}=${e.value}')
              .toList(),
        },
        'A',
      );
      // #endregion
      final selectedPlace = _selectionData?.placeCode;
      if (!mounted) {
        return;
      }
      setState(() {
        _dataset110m ??= dataset110m;
        _labels
          ..clear()
          ..addAll(labels);
        _levels
          ..clear()
          ..addAll(levels);
        _levelCounts = Map<int, int>.from(levelCounts);
        _visitCounts
          ..clear()
          ..addAll(visitCounts);
        _geometryToPlace = geometryToPlace;
        _recomputeDrawableStatsLocked();
        _totalScore = total;
        _drawOrders.clear();
        _updateDrawOrdersFromDataset(_dataset110m!);
        final fine = _dataset50m;
        if (fine != null) {
          _updateDrawOrdersFromDataset(fine);
        }
        _refreshActiveDatasetLocked();
        _renderState = const MapRenderReady();
      });
      if (_activeDataset == null) {
        throw const MapDataException('有効な地図データを初期化できませんでした。');
      }
      if (_desiredLod == MapLod.fine50m) {
        unawaited(_ensureFineDatasetLoaded());
      }
      if (selectedPlace != null && mounted) {
        await _selectPlace(selectedPlace, animateSheet: false);
      }
    } catch (error, stackTrace) {
      if (error is DatabaseException && error.isDatabaseClosedError()) {
        return;
      }
      _handleFatalMapError(error, stackTrace);
    }
  }

  void _handleFatalMapError(Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('MapPage load error: $error\n$stackTrace');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _renderState = MapRenderError(
        message: _mapLoadErrorMessage,
        details: error.toString(),
      );
      _activeDataset = null;
    });
  }

  void _refreshActiveDatasetLocked() {
    if (_lod == MapLod.fine50m && _dataset50m == null) {
      _lod = MapLod.coarse110m;
    }
    final dataset = _lod == MapLod.fine50m ? _dataset50m : _dataset110m;
    if (dataset == null) {
      _setFlatFallbackBounds();
      return;
    }
    _setActiveDataset(dataset);
  }

  void _setActiveDataset(FlatMapDataset dataset) {
    _activeDataset = dataset;
    _geometryBounds = dataset.boundsByGeometry;
    if (!kReleaseMode) {
      _debugParsedFeatures = dataset.geometries.length;
    }
    _recomputeDrawableStatsLocked();
  }

  void _setFlatFallbackBounds() {
    if (_geometryBounds.isNotEmpty) {
      return;
    }
    _geometryBounds = {
      _kAntarcticaGeometryId: const GeoBounds(
        minLon: -180,
        minLat: -90,
        maxLon: 180,
        maxLat: -60,
      ),
    };
  }

  void _recomputeDrawableStatsLocked() {
    final dataset = _activeDataset;
    if (dataset == null) {
      _hasDrawablePolygons = false;
      if (!kReleaseMode) {
        _debugMappedPolygons = 0;
        _debugDrawnPolygons = 0;
      }
      return;
    }
    final polygons = dataset.polygons;
    int mapped = 0;
    for (final polygon in polygons) {
      if (_geometryToPlace.containsKey(polygon.geometryId)) {
        mapped++;
      }
    }
    _hasDrawablePolygons = mapped > 0;
    if (!kReleaseMode) {
      _debugMappedPolygons = mapped;
      _debugDrawnPolygons = polygons.length;
    }
  }

  void _activateLod(MapLod lod) {
    final dataset = lod == MapLod.fine50m ? _dataset50m : _dataset110m;
    if (dataset == null) {
      _setFlatFallbackBounds();
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
      MapDatasetGuard.ensureUsable(dataset, label: 'countries_50m');
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
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Fine dataset load failed: $error\n$stackTrace');
      }
      if (mounted) {
        _showMessage('詳細地図の読み込みに失敗しました');
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
    if (!_isFiniteTransform(scale, translation)) {
      _handleFatalMapError(
        const MapDataException('ビュー変換の計算に失敗しました。'),
        StackTrace.current,
      );
      return false;
    }
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

  bool _isFiniteTransform(double scale, Offset translation) {
    return scale.isFinite && translation.dx.isFinite && translation.dy.isFinite;
  }

  void _setLoadingState() {
    if (!mounted) {
      return;
    }
    setState(() {
      _renderState = const MapRenderLoading();
    });
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
    _recordViewportTransform();
  }

  void _handleViewportChanged() {
    if (_isApplyingViewportTransform) {
      return;
    }
    _enforceViewportConstraints();
    _updateLodForCurrentView();
    _recordViewportTransform();
  }

  void _recordViewportTransform() {
    if (kReleaseMode || !mounted || !_kEnableDebugOverlay) {
      return;
    }
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = Offset(matrix.storage[12], matrix.storage[13]);
    if ((_debugScale - scale).abs() < 1e-3 &&
        (_debugTranslation - translation).distance < 0.5) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _debugScale = scale;
        _debugTranslation = translation;
      });
    });
  }

  String? get _fallbackNoticeText {
    if (_renderState is! MapRenderReady) {
      return null;
    }
    final dataset = _activeDataset;
    if (dataset == null) {
      return '地図データを初期化できませんでした';
    }
    if (_geometryToPlace.isEmpty || !_hasDrawablePolygons) {
      return 'Placeデータとの対応がみつからず、境界線のみ表示しています';
    }
    final metrics = _lastPaintMetrics;
    if (metrics.totalPolygons == 0) {
      return null;
    }
    if (metrics.filledPolygons == 0 &&
        metrics.outlineOnlyPolygons > 0 &&
        metrics.totalPolygons >= dataset.polygons.length ~/ 2) {
      return '塗り分けに必要なPlace情報を再同期してください';
    }
    return null;
  }

  @visibleForTesting
  bool get isFallbackActive => _fallbackNoticeText != null;

  @visibleForTesting
  MapRenderState get debugRenderState => _renderState;

  @visibleForTesting
  bool get hasDrawablePolygons => _hasDrawablePolygons;

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
    // #region agent log
    _debugLog('map_page.dart:_handleLongPress', 'Long press detected', {
      'position': '${position.dx},${position.dy}',
      'renderState': _renderState.runtimeType.toString(),
      'activeDatasetNotNull': _activeDataset != null,
    }, 'D');
    // #endregion
    final candidates = _hitTestCandidates(position);
    // #region agent log
    _debugLog('map_page.dart:_handleLongPress:candidates', 'Candidates found', {
      'count': candidates.length,
      'candidates': candidates.take(5).map((c) => c.placeCode).toList(),
    }, 'D');
    // #endregion
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
    final normalized = _normalizedFromLocal(position);
    if (normalized == null) {
      _updateCandidateDebug(0);
      return const <_PlaceCandidate>[];
    }
    final dataset = _activeDataset;
    if (dataset == null) {
      final fallbackOnly = _buildAntarcticaCandidate(normalized.dy);
      if (fallbackOnly != null) {
        _updateCandidateDebug(1);
        return [fallbackOnly];
      }
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
      final fallback = _buildAntarcticaCandidate(normalized.dy);
      if (fallback != null) {
        _updateCandidateDebug(1);
        return [fallback];
      }
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
    if (candidates.isEmpty) {
      final fallback = _buildAntarcticaCandidate(normalized.dy);
      if (fallback != null) {
        _updateCandidateDebug(1);
        return [fallback];
      }
    }
    _updateCandidateDebug(candidates.length);
    return candidates;
  }

  _PlaceCandidate? _buildAntarcticaCandidate(double normalizedY) {
    if (normalizedY < _kAntarcticaNormalizedThreshold) {
      return null;
    }
    if (!_labels.containsKey(_kAntarcticaPlaceCode)) {
      return null;
    }
    final drawOrder =
        (_drawOrders[_kAntarcticaGeometryId] ??
        _activeDataset?.geometries[_kAntarcticaGeometryId]?.drawOrder ??
        0);
    return _PlaceCandidate(
      placeCode: _kAntarcticaPlaceCode,
      drawOrder: drawOrder,
      displayName: _displayName(_kAntarcticaPlaceCode),
    );
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
    // Canvas is 3x wide, so divide by _worldSize and then normalize x to 0-1
    var normalizedX = scenePoint.dx / _worldSize;
    final normalizedY = scenePoint.dy / _worldSize;

    // Wrap x coordinate to 0-1 range (since we have 3 copies of the world)
    normalizedX = normalizedX % 1.0;
    if (normalizedX < 0) normalizedX += 1.0;

    final normalized = Offset(normalizedX, normalizedY);
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
    if (!_kEnableDebugOverlay) {
      _debugCandidateCount = count;
      return;
    }
    if (kReleaseMode || !mounted || _debugCandidateCount == count) {
      _debugCandidateCount = count;
      return;
    }
    setState(() {
      _debugCandidateCount = count;
    });
  }

  void _handlePaintMetrics(_MapPaintMetrics metrics) {
    _lastPaintMetrics = metrics;
    if (kReleaseMode || !mounted || !_kEnableDebugOverlay) {
      return;
    }
    if (_debugFillCount == metrics.filledPolygons &&
        _debugOutlineOnlyCount == metrics.outlineOnlyPolygons) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _debugFillCount = metrics.filledPolygons;
        _debugOutlineOnlyCount = metrics.outlineOnlyPolygons;
      });
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
    // Recreate controller to avoid "already attached" error when switching places
    _sheetController.dispose();
    _sheetController = DraggableScrollableController();
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
    final db = _db ?? await _openDatabase();
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
    // Color-blind friendly palette (Wong's palette inspired)
    // Cool to warm gradient: deeper visits = warmer colors
    switch (level) {
      case 0:
        return const Color(0xFF6B7280); // Neutral gray for unvisited
      case 1:
        return const Color(0xFF56B4E9); // Sky blue - transit only
      case 2:
        return const Color(0xFF009E73); // Teal/bluish-green - brief visit
      case 3:
        return const Color(0xFFF0E442); // Yellow - day trip
      case 4:
        return const Color(0xFFE69F00); // Orange - overnight stay
      case 5:
      default:
        return const Color(0xFFD55E00); // Vermillion/red-orange - residence
    }
  }

  String _levelShortLabel(int level) {
    switch (level) {
      case 1:
        return '乗継';
      case 2:
        return '通過';
      case 3:
        return '訪問';
      case 4:
        return '観光';
      case 5:
        return '居住';
      default:
        return '';
    }
  }

  Widget _buildLevelLegend() {
    final theme = Theme.of(context);
    return Container(
      key: const Key('map_level_legend'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Level',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          for (var level = 5; level >= 1; level--)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _colorForLevel(level),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 36,
                    child: Text(
                      'Lv.$level',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      _levelShortLabel(level),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_levelCounts[level] ?? 0}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addVisitFromSheet() async {
    // #region agent log
    _debugLog('map_page.dart:_addVisitFromSheet', 'Adding visit from sheet', {
      'placeCode': _selectionData?.placeCode,
    }, 'D');
    // #endregion
    final placeCode = _selectionData?.placeCode;
    if (placeCode == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditorPage(initialPlaceCode: placeCode),
      ),
    );
    // #region agent log
    _debugLog(
      'map_page.dart:_addVisitFromSheet:result',
      'Visit editor returned',
      {'result': result, 'mounted': mounted},
      'D',
    );
    // #endregion
    if (!mounted || result != true) return;
    _setLoadingState();
    await _loadData();
    // #region agent log
    _debugLog('map_page.dart:_addVisitFromSheet:afterLoad', 'After loadData', {
      'renderState': _renderState.runtimeType.toString(),
      'activeDatasetNotNull': _activeDataset != null,
      'hasDrawablePolygons': _hasDrawablePolygons,
    }, 'B');
    // #endregion
  }

  Future<void> _openDetailFromSheet() async {
    final placeCode = _selectionData?.placeCode;
    if (placeCode == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaceDetailPage(placeCode: placeCode)),
    );
    if (!mounted) return;
    _setLoadingState();
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
    final state = _renderState;
    if (state is MapRenderLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is MapRenderError) {
      return _MapErrorView(
        message: state.message,
        details: state.details,
        onRetry: _retryLoad,
      );
    }
    final dataset = _activeDataset;
    if (dataset == null) {
      return const Center(child: Text('地図データが初期化されていません'));
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
          onMetrics: _handlePaintMetrics,
        );
        // Canvas is 3x wide to allow seamless horizontal scrolling
        final canvas = SizedBox(
          width: _worldSize * 3,
          height: _worldSize,
          child: CustomPaint(painter: painter),
        );
        final viewer = InteractiveViewer(
          transformationController: _transformationController,
          minScale: _minScale ?? 1.0,
          maxScale: 20.0,
          panEnabled: true,
          scaleEnabled: true,
          constrained: false,
          boundaryMargin: EdgeInsets.zero,
          clipBehavior: Clip.none,
          child: canvas,
        );
        return MapGestureLayer(
          enabled: state is MapRenderReady && _activeDataset != null,
          onTap: _clearSelection,
          onLongPress: (position) => _handleLongPress(position),
          child: SizedBox.expand(child: viewer),
        );
      },
    );
  }

  void _retryLoad() {
    _setLoadingState();
    unawaited(_loadData());
  }

  Widget _buildGlobeMap() {
    // For Globe view, prefer the detailed 50m dataset
    final dataset = _dataset50m ?? _activeDataset;
    if (dataset == null) {
      // Trigger loading of 50m data if not already loaded
      _ensureFineDatasetLoaded();
      return const Center(child: CircularProgressIndicator());
    }

    return GlobeMapWidget(
      dataset: dataset,
      levels: _levels,
      colorResolver: _colorForLevel,
      geometryToPlace: _geometryToPlace,
      selectedPlaceCode: _selectionData?.placeCode,
      onCountryLongPressed: (placeCode) {
        _selectPlace(placeCode);
      },
    );
  }

  Widget _buildFlatPlaceholder() {
    return FlatMapUnderConstruction(
      onExit: () => setState(() => _isGlobe = true),
    );
  }

  Widget _buildSelectionSheet() {
    final data = _selectionData;
    if (data == null || _renderState is! MapRenderReady) {
      return const SizedBox.shrink();
    }
    return MapSelectionSheet(
      key: ValueKey(data.placeCode),
      controller: _sheetController,
      data: data,
      onAddVisit: _addVisitFromSheet,
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
                'Scale: ${_debugScale.toStringAsFixed(2)} '
                'Tx:${_debugTranslation.dx.toStringAsFixed(1)} '
                'Ty:${_debugTranslation.dy.toStringAsFixed(1)}\n'
                'Parsed: $_debugParsedFeatures · '
                'Polygons: $_debugDrawnPolygons · '
                'Mapped: $_debugMappedPolygons\n'
                'Fill: $_debugFillCount · Outline only: $_debugOutlineOnlyCount\n'
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
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _isGlobe ? _buildGlobeMap() : _buildFlatPlaceholder(),
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
              bottom: 16,
              right: 16,
              child: SafeArea(child: _buildLevelLegend()),
            ),
            _buildFallbackNotice(),
            if (_kEnableDebugOverlay && !kReleaseMode) _buildDebugOverlay(),
            if (_selectionData != null) _buildSelectionSheet(),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackNotice() {
    final message = _fallbackNoticeText;
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: SafeArea(
        child: IgnorePointer(
          ignoring: true,
          child: Container(
            key: const Key('map_fallback_notice'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
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
    required this.onMetrics,
  });

  final List<MapPolygon> polygons;
  final Map<String, int> levels;
  final Color Function(int) colorResolver;
  final Map<String, String> geometryToPlace;
  final String? selectedPlaceCode;
  final ValueChanged<_MapPaintMetrics>? onMetrics;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      onMetrics?.call(_MapPaintMetrics.zero);
      return;
    }

    // Draw ocean background - a pleasant blue color
    final oceanPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF4a90d9);
    canvas.drawRect(Offset.zero & size, oceanPaint);

    final fillPaint = Paint()..style = PaintingStyle.fill;
    // Canvas is now 3x wide, so each "world" is 1/3 of the width
    final worldWidth = size.width / 3.0;
    final scaleX = worldWidth;
    final scaleY = size.height;
    final strokeScale = (scaleX + scaleY) / 2.0;
    final fallbackStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x884a5568)
      ..strokeWidth = strokeScale == 0 ? 0 : 1.2 / strokeScale;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xAA0a0a0a)
      ..strokeWidth = strokeScale == 0 ? 0 : 1.6 / strokeScale;
    final highlightStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = strokeScale == 0 ? 0 : 2.5 / strokeScale;
    var filledCount = 0;
    var outlineOnlyCount = 0;

    // Draw 3 copies of the world map (left, center, right)
    for (int worldIndex = 0; worldIndex < 3; worldIndex++) {
      canvas.save();
      // Translate to the correct world position and scale
      canvas.translate(worldIndex * worldWidth, 0);
      canvas.scale(scaleX, scaleY);

      for (final polygon in polygons) {
        final placeCode = geometryToPlace[polygon.geometryId];
        final path = polygon.path;
        if (placeCode == null) {
          canvas.drawPath(path, fallbackStrokePaint);
          if (worldIndex == 1)
            outlineOnlyCount++; // Count only once (center world)
          continue;
        }
        final level = levels[placeCode] ?? 0;
        final isSelected = placeCode == selectedPlaceCode;
        final baseColor = colorResolver(level);
        fillPaint.color = isSelected
            ? baseColor
            : baseColor.withValues(alpha: 0.85);
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, isSelected ? highlightStrokePaint : strokePaint);
        if (worldIndex == 1) filledCount++; // Count only once (center world)
      }
      canvas.restore();
    }

    onMetrics?.call(
      _MapPaintMetrics(
        totalPolygons: polygons.length,
        filledPolygons: filledCount,
        outlineOnlyPolygons: outlineOnlyCount,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FlatMapPainter oldDelegate) {
    return oldDelegate.polygons != polygons ||
        oldDelegate.levels != levels ||
        oldDelegate.geometryToPlace != geometryToPlace ||
        oldDelegate.selectedPlaceCode != selectedPlaceCode ||
        oldDelegate.onMetrics != onMetrics;
  }
}

class _MapPaintMetrics {
  const _MapPaintMetrics({
    required this.totalPolygons,
    required this.filledPolygons,
    required this.outlineOnlyPolygons,
  });

  final int totalPolygons;
  final int filledPolygons;
  final int outlineOnlyPolygons;

  static const zero = _MapPaintMetrics(
    totalPolygons: 0,
    filledPolygons: 0,
    outlineOnlyPolygons: 0,
  );
}

class _MapErrorView extends StatelessWidget {
  const _MapErrorView({
    required this.message,
    required this.onRetry,
    this.details,
  });

  final String message;
  final String? details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('再読み込み')),
          ],
        ),
      ),
    );
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
