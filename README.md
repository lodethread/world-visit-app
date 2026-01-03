# world-visit-app

Keikoku (world visit) MVP の Flutter クライアントです。すべての地図・マスターデータをアプリ内に同梱し、オフラインでも旅行ログを編集できます。

## セットアップ

1. Flutter (stable、3.10 以降) を用意します。
2. ルートで `flutter pub get` を実行して依存関係を解決します。
3. エミュレーター/実機を起動し、`flutter run` でアプリを起動します。

## CI / ビルド

- Linux ランナーでは `dart format --set-exit-if-changed .`、`flutter analyze`、`flutter test`、`flutter build apk` を実行します。
- macOS ランナーでは iOS 向けに `flutter build ios --no-codesign` を実行します。
- これらに先立ち `flutter pub get` を毎回実行し、依存を同期します。

## Import / Export (keikoku v1)

- Settings → Data management から JSON / CSV v1 の ImportFlow を利用できます。
- JSON: `format="keikoku"`, `version=1`。`place_code` で Places を参照し、未知コードはエラー扱いでスキップします。未定義フィールドは無視されます。
- CSV: UTF-8 (BOM 任意) でヘッダ必須。`tags` は `;` 区切りで、タグに `;` を含めることはできません。
- ImportFlow は「ファイル選択 → Preflight → Preview（集計） → 実行 → 結果/issue一覧」を踏襲し、デフォルトは不正行スキップ、厳格モードでは 1 件のエラーで全体中断します。

## Map

- Map 画面は Mapbox 依存を持たない CustomPainter 製の平面 Web Mercator マップです。`assets/places/places.geojson.gz` を gzip 展開して描画し、place_stats.max_level で色分けします。
- Globe トグルは MVP では「Under construction」を表示し、将来の球面実装のプレースホルダーとして扱います。

## データソース

- `assets/places/*.json` と `assets/places/places.geojson.gz` は repo に同梱された最小データセットです。`place_code` を唯一キーとして DB/GeoJSON/JSON 間で一致させています。
- 境界線・地理情報は便宜的に簡略化されており、行政境界の厳密さは保証しません。今後のアップデートで順次精緻化していきます。

## Stats 画面

- Settings → Stats から経国値（Σ place_stats.max_level）とレベル別の Place 件数 (0–5) を確認できます。
- 集計は `place_stats` テーブルを直接参照するため追加のネットワークや API は不要です。
