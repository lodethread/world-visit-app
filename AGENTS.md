# AGENTS.md — Keikoku (経国値) MVP 実装ガイド（Codex / Agent 用）

このリポジトリは「経国値」MVP（写真なし・Place固定同梱・オフライン対応）を実装するためのものです。
Agent は **このファイルのルール**と **仕様書**に従って変更を提案・実装してください。

---

## 0. 仕様の唯一の正（Single Source of Truth）

- 仕様書（必読）  
  - `docs/keikoku_requirements_mvp.md`

- 本ファイル（AGENTS.md）は「実装の迷いを消すための運用・規約」と「技術的な固定方針」を定義します。  
  仕様書と矛盾する場合は **仕様書が優先**です。

---

## 1. MVPのゴール（Definition of Done）

### 1.1 リポジトリとしての「完成」の定義（ユーザー定義の完了条件）
- 仕様書に定義されたMVP機能が実装されている
- CIがグリーンになること（最低限）：
  - `dart format --set-exit-if-changed .`
  - `flutter analyze`
  - `flutter test`
  - `flutter build apk`
  - `flutter build ios --no-codesign`（CIのみ / macOS runner）

> ストア提出（署名・TestFlight/Play Console）はスコープ外。

### 1.2 品質の最低条件
- オフライン（機内モード）で起動しても落ちない
- 地図（2D/3D）切替、長押し選択、旅行CRUD、検索、Import/Export が動く
- 仕様書の「受け入れ基準（Done定義）」を満たす

---

## 2. 絶対に守るべき不変条件（Non‑negotiables）

1) **`place_code` は全ての参照キー**  
   - DB / JSON / CSV / GeoJSON Feature.id で一致させる  
   - Visit は `place_code` を参照する（内部IDで参照しない）

2) **Placeマスタは固定同梱のみ**  
   - ユーザーによるカスタムPlace追加は実装しない

3) **スコア集計は max方式**  
   - `Placeスコア = MAX(visit.level)`  
   - 経国値 = Σ Placeスコア

4) **MVPでは写真は実装しない**

5) **オフライン成立が前提**  
   - 地図はベースマップ依存にしない（同梱GeoJSONのみで成立させる）
   - Import/Export もオフラインで完結する

6) **Importは安全側に倒す**  
   - 既定モードは「不正レコードはスキップして取り込み続行（通常モード）」
   - 厳格モード（任意）は「1件でもエラーがあれば全体中断」

---

## 3. 技術スタックの固定（迷いを消す）

### 3.1 UI/アプリ
- Flutter（stable） + Dart
- Navigation：`go_router` を推奨  
  - もし既に導入済みのナビゲーションがあればそれに揃える
- 状態管理：依存がない場合は `flutter_riverpod` を推奨  
  - 既に provider/bloc 等があるなら統一を優先

### 3.2 DB
- SQLite
- 実装方針（推奨・固定）：
  - DB操作は `sqflite`（モバイル）
  - テスト用は `sqflite_common_ffi`（Linux CIで動かす）
  - **DDL/Triggerは仕様書どおりの raw SQL** を migrations で実行する  
    （ORM/コード生成で悩まないため）

### 3.3 地図
- Mapbox を第一案として採用する（2D/3D投影切替が中核のため）
- Flutter：`mapbox_maps_flutter` を使用（既に別案が採用済みならそれに統一）

> Mapbox token はビルド・実行に関わるため、アプリは **トークン無しでも落ちない**設計にすること。  
> トークンが無い場合は Map画面に明確な案内を出す（例：Settingsで設定する/ビルド時にdart-defineする等）。

---

## 4. リポジトリ構造（推奨）

- `docs/keikoku_requirements_mvp.md` … 仕様書
- `assets/places/`
  - `places.geojson.gz`
  - `place_master.json`
  - `place_aliases.json`
  - `place_master_meta.json`
- `assets/map/`
  - `style_mercator.json`
  - `style_globe.json`

- `lib/`
  - `app/`（ルーティング・テーマ）
  - `features/map/`
  - `features/place/`
  - `features/visit/`
  - `features/import_export/`
  - `data/`（db、repositories、models）
  - `util/`（normalize、date utilities、error model）
- `tools/build_places/`（地図データ生成。MVPは“再生成しない”運用）

---

## 5. 生成物（assets/places/*）の運用ルール

### 5.1 重要：Agentは勝手に再生成しない
- `assets/places/*` は **生成済み成果物としてコミット済み**である前提
- これらの更新は、明示的な「地図データ更新PR」に限定する
  - 通常の機能PRで改変しない

### 5.2 同梱データの契約
- `places.geojson.gz` の Feature は必ず：
  - `Feature.id == place_code`（文字列）
  - `properties.place_code == place_code`
  - `properties.draw_order` がある（数値）
- `place_master.json` と GeoJSON の place_code は完全一致（欠落/余剰なし）

---

## 6. DB（schema/migrations）実装ルール

### 6.1 スキーマ
- 仕様書の DDL をそのまま採用する（テーブル・インデックス・CHECK制約）
- `place_stats` は必須（max_level/visit_count/last_visit_date を保持）

### 6.2 Trigger（必須）
- insert/update/delete で `place_stats` を再計算する Trigger を作る
- Agentは「アプリコードで更新」へ勝手に変更しない（仕様固定）

### 6.3 Place同期（Bootstrap）
起動時に毎回：
1) `assets/places/place_master_meta.json` の `hash` を meta に保存/比較
2) 差分があれば：
   - place を `place_code` Upsert
   - place_alias を洗い替え（place_code単位）
   - place_stats に place_code 全件ぶんの行を補完

---

## 7. 地図（Mapbox）実装ルール

### 7.1 オフライン成立のためのスタイル
- オンラインスタイル（Standardなど）を使わない
- `assets/map/style_mercator.json` と `assets/map/style_globe.json` を用意
  - background + 自前GeoJsonSource + fill/line/highlight のみ
  - glyph/sprite 依存（文字ラベル）は MVPでは入れない

### 7.2 2D/3D 切替
- トグルでスタイルを `loadStyleJson` し直す（確実性優先）
  - Mercator: `"projection": {"name":"mercator"}`
  - Globe: `"projection": {"name":"globe"}`

### 7.3 GeoJsonSource
- `GeoJsonSource` に inline GeoJSON を投入する（解凍して文字列化）
- `generateId=false` を維持して Feature.id を壊さない

### 7.4 色更新（差分）
- `place_stats.max_level` を feature-state の `level` にセットして色分けする
- Visit保存/削除/移動で影響した place_code のみ state を更新する
- Mapロード時は `max_level>0` の Place だけ state を貼る（軽量化）

### 7.5 長押し選択
- `queryRenderedFeatures` を使って候補Featureを取得
- 候補が複数なら「候補選択シート」を必ず出す
- 候補の並び：
  1) `draw_order` 降順
  2) 安定ソート（name_en等）

---

## 8. 検索（PlacePicker/Trips/Tags）実装ルール

### 8.1 正規化関数（normalize）
以下を必ず守る（仕様書に準拠）：
- trim
- 連続空白の圧縮
- 英字小文字化
- Unicode NFKD
- combining mark除去
- 記号の除去/空白扱い

### 8.2 PlacePicker（インメモリ検索）
- place + place_alias を起動時にロードしてインデックス化（place数は少ない前提）
- マッチ種別：
  - Exact > Prefix > Substring
- 空クエリ時：
  - 最近訪問（place_stats.last_visit_date 降順 上位）
  - それ以外は sort_order

### 8.3 Trips検索（DB）
- 大量データに備えDB検索を基本とする
- Place絞り込みは PlacePicker インデックスで候補place_codeを先に抽出し `IN (...)` を使う

---

## 9. Import/Export 実装ルール（正式仕様に準拠）

### 9.1 JSON（keikoku v1）
- `format="keikoku"`, `version=1`
- Place参照は `place_code`
- unknown fields は無視（前方互換）
- `place_code` 未知 → そのVisitをスキップして issues に記録

### 9.2 CSV（visits.csv v1）
- UTF-8（可能ならBOM）
- ヘッダ必須
- tags は `;` 区切り
  - タグ名に `;` を含めるのは禁止（エラー）

### 9.3 ImportFlow UI（必須）
- ファイル選択 → Preflight → Preview（集計） → 実行 → 結果（issues一覧）
- 既定は通常モード（不正行スキップ）
- 厳格モード（トグル）では 1件でもエラーで全体中断

### 9.4 Issue（エラー/警告）モデル
- severity: error/warning/info
- code: 仕様書のコードセット
- location: JSON pointer or CSV row/column
- context: visit_id/place_code/raw_value（可能なら）

---

## 10. テスト方針（最低限）

### 10.1 必須ユニット/DBテスト
- 日付バリデーション（start<=end、同日OK、片側NULL OK）
- place_stats trigger 整合（insert/update/delete/place移動）
- tag名ユニーク（name_norm）
- Trips並び順（start_date優先、無ければcreated_at）

### 10.2 E2E（手動でも可、将来 integration_test 化）
- オフライン起動
- Place長押し→詳細
- 旅行追加→地図色更新
- 直前旅行複製
- JSON/CSV export→import

---

## 11. PR運用（Agentの作業単位）

### 11.1 1PRの粒度
- 1PR = 1テーマ（地図、DB、Import、UIなど）
- 変更行数が多い場合は分割する

### 11.2 PRに必須の要素
- 仕様書のどの要件を満たしたか（箇条書き）
- 主要画面のスクショ/簡易GIF（可能なら）
- テスト実行結果（少なくとも `flutter test`）
- 破壊的変更が無いこと（place_code/データ互換）

---

## 12. コマンド（Agentが最小限走らせる）

### 12.1 変更前提（必須）
- `flutter pub get`

### 12.2 PR提案前（必須）
- `dart format --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`

### 12.3 可能なら（推奨）
- `flutter build apk`
- iOSビルドはCIに任せる（macOSが必要なため）
  - `flutter build ios --no-codesign` は GitHub Actions で実行

---

## 13. やってはいけないこと（Anti‑patterns）
- `place_code` の仕様を変更する
- Placeマスタをユーザー追加可能にする
- スコア集計を合計方式に変える
- assets/places を理由なく再生成・差し替えする
- Importで未知place_codeを「勝手に新規Place化」する
- ネットが無いと起動できない設計にする（MVP違反）

---

## 14. 迷った時の優先順位
1) `docs/keikoku_requirements_mvp.md`（仕様）
2) この `AGENTS.md`（実装方針・運用）
3) 既存コードの一貫性（導入済みライブラリ/アーキテクチャ）
4) 依存追加は最小（MVPで必要なものだけ）

以上。
