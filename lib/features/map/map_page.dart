import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:sqflite/sqflite.dart';

import 'package:world_visit_app/data/db/app_database.dart';
import 'package:world_visit_app/features/place/ui/place_detail_page.dart';

const String mapboxAccessToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
  defaultValue: '',
);

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool _isGlobe = false;
  int _keikokuTotal = 0;
  MapboxMap? _mapboxMap;
  Database? _db;
  String? _geoJsonString;
  bool _loadingData = true;
  bool _styleReady = false;
  Map<String, _PlaceLabel> _placeLabels = {};
  Map<String, int> _latestLevels = {};

  @override
  void initState() {
    super.initState();
    if (mapboxAccessToken.isNotEmpty) {
      MapboxOptions.setAccessToken(mapboxAccessToken);
    }
    _loadPlaceData();
  }

  @override
  void dispose() {
    _mapboxMap = null;
    _db?.close();
    super.dispose();
  }

  Future<void> _loadPlaceData() async {
    setState(() => _loadingData = true);
    final db = _db ?? await AppDatabase().open();
    _db ??= db;
    final placeRows = await db.query('place');
    final statsRows = await db.query('place_stats');

    final labels = <String, _PlaceLabel>{};
    for (final row in placeRows) {
      labels[row['place_code'] as String] = _PlaceLabel(
        nameJa: row['name_ja'] as String,
        nameEn: row['name_en'] as String,
      );
    }
    final latestLevels = <String, int>{};
    int total = 0;
    for (final row in statsRows) {
      final level = (row['max_level'] as int?) ?? 0;
      latestLevels[row['place_code'] as String] = level;
      total += level;
    }
    if (!mounted) return;
    setState(() {
      _placeLabels = labels;
      _latestLevels = latestLevels;
      _keikokuTotal = total;
      _loadingData = false;
    });
    await _updateFeatureStates();
  }

  Future<void> _ensureGeoJsonLoaded() async {
    if (_geoJsonString != null) return;
    final data = await rootBundle.load('assets/places/places.geojson.gz');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final decoded = GZipDecoder().decodeBytes(bytes);
    _geoJsonString = utf8.decode(decoded);
  }

  Future<void> _loadStyle() async {
    if (_mapboxMap == null) return;
    _styleReady = false;
    await _ensureGeoJsonLoaded();
    final styleAsset = _isGlobe
        ? 'assets/map/style_globe.json'
        : 'assets/map/style_mercator.json';
    final styleJson = await rootBundle.loadString(styleAsset);
    await _mapboxMap!.style.setStyleJSON(styleJson);
    await _addSourceAndLayers();
    await _updateFeatureStates();
  }

  Future<void> _addSourceAndLayers() async {
    if (_mapboxMap == null || _geoJsonString == null) return;
    final style = _mapboxMap!.style;
    final exists = await style.styleSourceExists('places-source');
    if (exists) {
      await style.removeStyleLayer('places-outline');
      await style.removeStyleLayer('places-fill');
      await style.removeStyleSource('places-source');
    }
    await style.addSource(
      GeoJsonSource(id: 'places-source', data: _geoJsonString),
    );
    await style.addLayer(
      FillLayer(
        id: 'places-fill',
        sourceId: 'places-source',
        fillOpacity: 0.8,
        fillColorExpression: _levelColorExpression,
        fillSortKeyExpression: const ['get', 'draw_order'],
        fillOutlineColor: Colors.black.withValues(alpha: 0.4).toARGB32(),
      ),
    );
    await style.addLayer(
      LineLayer(
        id: 'places-outline',
        sourceId: 'places-source',
        lineColor: Colors.white.withValues(alpha: 0.6).toARGB32(),
        lineWidth: 0.5,
      ),
    );
    _styleReady = true;
  }

  List<Object> get _levelColorExpression => [
    'interpolate',
    ['linear'],
    [
      'coalesce',
      [
        'to-number',
        ['feature-state', 'level'],
      ],
      0,
    ],
    0,
    '#1b263b',
    1,
    '#3a86ff',
    2,
    '#00b4d8',
    3,
    '#80ed99',
    4,
    '#ffd166',
    5,
    '#ef476f',
  ];

  Future<void> _updateFeatureStates() async {
    if (_mapboxMap == null || !_styleReady) return;
    for (final entry in _latestLevels.entries) {
      await _mapboxMap!.setFeatureState(
        'places-source',
        null,
        entry.key,
        jsonEncode({'level': entry.value}),
      );
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _loadStyle();
  }

  void _handleLongTap(MapContentGestureContext gestureContext) {
    unawaited(_onLongTap(gestureContext));
  }

  Future<void> _onLongTap(MapContentGestureContext gestureContext) async {
    final map = _mapboxMap;
    if (map == null || !_styleReady) return;
    final geometry = RenderedQueryGeometry.fromScreenCoordinate(
      gestureContext.touchPosition,
    );
    final features = await map.queryRenderedFeatures(
      geometry,
      RenderedQueryOptions(layerIds: ['places-fill']),
    );
    final codes = <String>{};
    for (final feature in features) {
      final data = feature?.queriedFeature.feature;
      final props = data?['properties'] as Map?;
      final placeCode = (props?['place_code'] ?? props?['placeCode'])
          ?.toString();
      if (placeCode != null) {
        codes.add(placeCode);
      }
    }
    if (codes.isEmpty) return;
    final selected = await _selectPlaceFromCandidates(codes.toList());
    if (selected != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaceDetailPage(placeCode: selected)),
      );
      if (mounted) {
        await _loadPlaceData();
      }
    }
  }

  Future<String?> _selectPlaceFromCandidates(List<String> placeCodes) async {
    if (placeCodes.length == 1) {
      return placeCodes.first;
    }
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('場所を選択')),
              for (final code in placeCodes)
                ListTile(
                  title: Text(_placeLabels[code]?.display ?? code),
                  onTap: () => Navigator.of(context).pop(code),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTokenMissing() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'MAPBOX_ACCESS_TOKEN が設定されていません。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'flutter run --dart-define MAPBOX_ACCESS_TOKEN=your_token',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mapboxAccessToken.isEmpty) {
      return _buildTokenMissing();
    }
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              key: ValueKey(_isGlobe),
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(139.767, 35.681)),
                zoom: 1.5,
              ),
              styleUri: MapboxStyles.MAPBOX_STREETS,
              onMapCreated: _onMapCreated,
              onLongTapListener: _handleLongTap,
            ),
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
                    '経国値: $_keikokuTotal',
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
                        onPressed: () {
                          if (_isGlobe) {
                            setState(() => _isGlobe = false);
                            _loadStyle();
                          }
                        },
                        child: Text(
                          '2D',
                          style: TextStyle(
                            color: _isGlobe
                                ? Colors.white70
                                : Colors.amberAccent,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (!_isGlobe) {
                            setState(() => _isGlobe = true);
                            _loadStyle();
                          }
                        },
                        child: Text(
                          '3D',
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
          if (_loadingData)
            const Positioned(
              bottom: 16,
              left: 16,
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _PlaceLabel {
  const _PlaceLabel({required this.nameJa, required this.nameEn});
  final String nameJa;
  final String nameEn;
  String get display => '$nameJa / $nameEn';
}
