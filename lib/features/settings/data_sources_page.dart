import 'package:flutter/material.dart';

class DataSourcesPage extends StatelessWidget {
  const DataSourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About / Data sources')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('経国値マップのデータソース', style: textTheme.titleLarge),
          const SizedBox(height: 16),
          _Section(
            title: 'Natural Earth',
            description:
                '世界地図の基礎データは '
                'Public Domain の Natural Earth を利用しています。'
                'ポリゴンや国境線は Natural Earth の 50m / 110m 解像度をもとに'
                'tool/map で加工しています。',
          ),
          _Section(
            title: 'world-atlas (TopoJSON)',
            description:
                'TopoJSON 配布物（@topojson/world-atlas）を使用し、'
                'countries-50m / countries-110m から GeoJSON を生成しています。'
                '生成スクリプトは tool/map 内にあり、リポジトリ内で再現できます。',
          ),
          _Section(
            title: '境界の扱い',
            description:
                '本アプリの境界表示は便宜上のものであり、'
                'いかなる政治的主張も行いません。HK/MO/PR/TW/PS/EH/XK など'
                '争点/依存地域も place_code に基づき管理し、統計のみを目的にしています。',
          ),
          _Section(
            title: '生成スクリプト',
            description:
                'マップおよび Place マスタは tool/map と tool/places の'
                'スクリプトから生成され、CIで検証されています。'
                '再生成が必要な場合は README の手順に従ってください。',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(description),
            ],
          ),
        ),
      ),
    );
  }
}
