import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_visit_app/data/place_assets/place_assets_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads place assets and deduplicates aliases', () async {
    final bundle = _FakeBundle({
      'assets/places/place_master.json':
          '[{"place_code":"JP","type":"country","name_ja":"日本","name_en":"Japan","is_active":true,"sort_order":1,"draw_order":2}]',
      'assets/places/place_aliases.json': '{"JP":["Nippon","Nippon","Japan"]}',
      'assets/places/place_master_meta.json':
          '{"hash":"hash","revision":"rev"}',
    });

    final loader = PlaceAssetsLoader(bundle: bundle);
    final data = await loader.load();

    expect(data.places, hasLength(1));
    expect(data.places.first.placeCode, 'JP');
    expect(data.aliases['JP'], ['Nippon', 'Japan']);
    expect(data.meta.hash, 'hash');
  });

  test('duplicate place codes throw error', () async {
    final bundle = _FakeBundle({
      'assets/places/place_master.json':
          '[{"place_code":"JP","type":"country","name_ja":"日本","name_en":"Japan","is_active":true,"sort_order":1,"draw_order":2},{"place_code":"JP","type":"country","name_ja":"日本","name_en":"Japan","is_active":true,"sort_order":1,"draw_order":2}]',
      'assets/places/place_aliases.json': '{"JP":[]}',
      'assets/places/place_master_meta.json':
          '{"hash":"hash","revision":"rev"}',
    });

    final loader = PlaceAssetsLoader(bundle: bundle);
    expect(loader.load(), throwsA(isA<FormatException>()));
  });
}

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this._values);

  final Map<String, String> _values;

  @override
  Future<ByteData> load(String key) {
    final value = _values[key];
    if (value == null) {
      throw StateError('Missing asset: $key');
    }
    final buffer = Uint8List.fromList(utf8.encode(value)).buffer;
    return Future.value(ByteData.view(buffer));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = _values[key];
    if (value == null) {
      throw StateError('Missing asset: $key');
    }
    return value;
  }
}
