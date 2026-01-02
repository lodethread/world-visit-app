import 'package:flutter_test/flutter_test.dart';
import 'package:world_visit_app/util/normalize.dart';

void main() {
  test('normalizeText removes diacritics and symbols', () {
    expect(normalizeText('  Café   du  Monde  '), 'cafe du monde');
    expect(normalizeText('東京	駅'), '東京 駅');
    expect(normalizeText('Hello---World!!!'), 'hello world');
  });
}
