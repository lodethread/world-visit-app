# World Place Master Generator

このディレクトリは `assets/places/place_master*.json` を「世界全体の Place マスタ」に再生成するためのワークスペースです。CI では実行せず、地図データ更新時のみローカルで実行します。

## 目的
- Map で同梱している `assets/map/countries_50m.geojson.gz` をソースに、全世界の place_code/geometry_id 対応表を生成する。
- 生成物を `PlaceAssetsLoader` → `PlaceSyncService` に読み込ませ、DB/各画面で世界全体を扱えるようにする。

## 入力
- `assets/map/countries_50m.geojson.gz`: world-atlas 50m ベースの GeoJSON（Feature.id = geometry_id）。
- `tool/places/generate_places.mjs`: 生成スクリプト（Node.js）。

## 生成手順
```bash
cd tool/places
npm install   # 初回のみ
npm run generate
```

## 生成物
コマンド実行後に以下が更新されます。
- `assets/places/place_master.json`
- `assets/places/place_aliases.json`
- `assets/places/place_master_meta.json`

どちらのファイルもコミット対象です。差分が非常に大きいため、1PRにまとめてレビューしやすい説明を記載してください。

## 注意事項
- world-atlas の更新に追従する場合は、必ずこのスクリプトで再生成すること。
- 生成結果の件数や contested region (HK/MO/PR/TW/PS/EH/XK) が揃っていることをテストで確認してください。
- 生成後は `flutter pub get && flutter test` など通常のCIコマンドを忘れずに実行してください。
