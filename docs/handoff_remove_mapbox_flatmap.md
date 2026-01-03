# feature/remove-mapbox-flatmap 引き継ぎメモ（2026-01-03）

## 現状概要
- 作業ブランチ: `feature/remove-mapbox-flatmap`
- 直近で Mapbox 依存を完全削除し、`lib/features/map` 一式をカスタム描画のフラットマップ実装に差し替え済み。
- `FlatMapLoader`/`PlacePolygon` を拡張し、GeoJSON (gzip) から draw_order・バウンディングボックス・穴付きポリゴンを解釈できる状態。
- `MapPage` は 2D/3D トグル、経国値表示、長押しでの候補シート→ `PlaceDetailPage` 遷移まで実装済み。球面側は「Under construction」メッセージ表示。
- GeoJSON/ジオメトリ用のユニットテスト（loader/geometry/map_page widget）を追加済み。

## 未完了タスク
1. `dart format --set-exit-if-changed .` がローカル Flutter SDK の sandbox 制限で失敗している。/opt/homebrew/share/flutter を丸ごとコピーしたが、SDK 内ファイルのフォーマットにまで踏み込みエラーになった。
2. `flutter analyze` / `flutter test` 未実行。`test/features/map/place_polygon_test.dart` を追加したので、少なくともこのディレクトリでのテスト実行が必要。
3. Mapbox 関連ファイルが全て削除されたか、README 等に古い記述が残っていないか最終確認が未実施。
4. `.dart_tool/` を削除した状態のため、再度 `flutter pub get` が必要。

## 既知の課題・リスク
- Flutter SDK をリポジトリ内にコピーした際、`dart format .` が SDK 自体を対象にしてしまう。→ 今後は `dart format lib features map ...` のように対象パスを限定、あるいは `pub global run flutter_plugin_tools format` 等は使わず、公式 Flutter SDK を（sandbox で）直接実行できるよう再設定が必要。
- `assets/places/places.geojson.gz` は最小 3 件 (JP/US/TW) のみ。同梱仕様との整合は次フェーズ要確認。
- Map のヒットテストは `PlacePolygon.containsPoint` による簡易実装のため、高解像度データ投入時のパフォーマンス検証が未実施。

## 次担当者向け推奨手順
1. `flutter pub get` を再実行して `.dart_tool/` を再生成してください。
2. Flutter SDK を sandbox 内で通常通り実行できるか確認し、`dart format --set-exit-if-changed .` を走らせる。
   - 問題が続く場合は `dart format lib test` のように対象をアプリディレクトリに限定し、SDK ディレクトリが含まれないようにする。
3. `flutter analyze` → `flutter test` を通し、Map 関連テストの成功を確認する。
4. Mapbox 関連の残骸が無いか `rg -n "mapbox" -n` で検索し、必要なら README 等も更新する。
5. ここまで完了後、`git status` で差分を確認し、仕様通りならコミット（例: "Remove Mapbox and add flat map MVP"）。

## 参考
- 変更主要ファイル: `lib/features/map/map_page.dart`, `lib/features/map/data/flat_map_loader.dart`, `lib/features/map/flat_map_geometry.dart`, `test/features/map/*`, `assets/places/places.geojson.gz`, `pubspec.yaml`
- 追加テスト: `test/features/map/flat_map_loader_test.dart`, `flat_map_geometry_test.dart`, `map_page_test.dart`, `place_polygon_test.dart`

以上。EOF
