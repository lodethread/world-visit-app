# world-visit-app

Keikoku (world visit) MVP の Flutter クライアントです。すべての地図・マスターデータをアプリ内に同梱し、オフラインでも旅行ログを編集できます。

## セットアップ

1. Flutter (stable、3.22 以降) を用意します。
2. ルートで `flutter pub get` を実行して依存関係を解決します。
3. エミュレーター/実機を起動し、`flutter run` でアプリを起動します。

## 機能概要

### Globe タブ
- **Globe ビュー**: 3D地球儀で訪問レベル別に国を色分け表示
- **Spark ビュー**: 訪問済み国が金色にキラキラ輝く演出、背景に星空アニメーション
- 国を長押しで選択、詳細シートから旅行追加・履歴閲覧が可能
- 経国値（総合スコア）を画面上部中央にスタイリッシュに表示
- Legend はトグル式で表示/非表示を切り替え可能

### Trips タブ
- 旅行履歴の一覧表示
- タグ・日付でのフィルタリング

### Settings タブ
- Import/Export (JSON/CSV)
- Stats（経国値・レベル別集計）
- テーマ設定

## CI / ビルド

- Linux ランナーでは `dart format --set-exit-if-changed .`、`flutter analyze`、`flutter test` を実行します。
- macOS ランナーでは iOS 向けに `flutter build ios --no-codesign` を実行します。
- これらに先立ち `flutter pub get` を毎回実行し、依存を同期します。

## Import / Export (keikoku v1)

- Settings → Data management から JSON / CSV v1 の ImportFlow を利用できます。
- JSON: `format="keikoku"`, `version=1`。`place_code` で Places を参照し、未知コードはエラー扱いでスキップします。未定義フィールドは無視されます。
- CSV: UTF-8 (BOM 任意) でヘッダ必須。`tags` は `;` 区切りで、タグに `;` を含めることはできません。
- ImportFlow は「ファイル選択 → Preflight → Preview（集計） → 実行 → 結果/issue一覧」を踏襲し、デフォルトは不正行スキップ、厳格モードでは 1 件のエラーで全体中断します。

## Map 実装

- Map 画面は Mapbox 依存を持たない CustomPainter 製の 3D Globe ビューです。
- `assets/map/countries_50m.geojson.gz` を gzip 展開し、`geometry_id` → `place_code` のマッピングを通じて place_stats.max_level で色分けします。
- レベル別カラーは色覚多様性に配慮した Wong パレットを採用（乗継/通過/訪問/観光/居住）。
- Globe/Spark の2つの表示モードを切り替え可能。
- Geometry は Natural Earth / world-atlas (TopoJSON) をビルド時に前処理しており、Kosovo など id 未付与の地域には `XK` を割り当てています。

## データソース

- `assets/places/*.json` は repo に同梱された Place マスタデータです。`place_code` (ISO alpha-2 + XK/XNC) をアプリ内部IDとして統一しています。
- 地図ポリゴンは Natural Earth ベースの world-atlas TopoJSON (`tool/map/build_assets.mjs`) を変換し、`geometry_id` (ISO numeric + XK) を Feature.id として扱います。`geometry_id`→`place_code` を突き合わせることで HK/MO/PR/TW/PS/EH/XK を独立の塗り分け対象にしています。
- 境界線・地理情報は便宜的に簡略化されており、行政境界の厳密さは保証しません。今後のアップデートで順次精緻化していきます。

## Stats 画面

- Settings → Stats から経国値（Σ place_stats.max_level）とレベル別の Place 件数 (0–5) を確認できます。
- 集計は `place_stats` テーブルを直接参照するため追加のネットワークや API は不要です。
