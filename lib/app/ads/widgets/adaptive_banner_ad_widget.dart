import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_service.dart';

/// Adaptive Bannerを表示するウィジェット
class AdaptiveBannerAdWidget extends StatefulWidget {
  const AdaptiveBannerAdWidget({super.key});

  @override
  State<AdaptiveBannerAdWidget> createState() => _AdaptiveBannerAdWidgetState();
}

class _AdaptiveBannerAdWidgetState extends State<AdaptiveBannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  double? _adHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAd();
  }

  Future<void> _loadAd() async {
    // 既にロード済みまたは非対応プラットフォームの場合はスキップ
    if (_bannerAd != null || !AdService.instance.isSupported) return;

    final width = MediaQuery.of(context).size.width;

    final ad = await AdService.instance.loadBannerAd(
      width: width,
      onAdLoaded: (ad) {
        if (!mounted) {
          ad.dispose();
          return;
        }
        setState(() {
          _bannerAd = ad as BannerAd;
          _isLoaded = true;
          _adHeight = ad.size.height.toDouble();
        });
      },
      onAdFailedToLoad: (ad, error) {
        debugPrint('[AdaptiveBannerAdWidget] Failed to load: ${error.message}');
        ad.dispose();
      },
    );

    if (ad == null && mounted) {
      debugPrint('[AdaptiveBannerAdWidget] Could not get adaptive banner size');
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 非対応プラットフォームまたは広告ロード前は非表示
    if (!AdService.instance.isSupported || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: _adHeight,
      alignment: Alignment.center,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
