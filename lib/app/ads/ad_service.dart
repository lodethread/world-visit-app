import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob広告を管理するサービスクラス
class AdService {
  AdService._();

  static final AdService _instance = AdService._();
  static AdService get instance => _instance;

  bool _isInitialized = false;

  /// AdMobの初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    // iOS/Androidのみ初期化
    if (!Platform.isIOS && !Platform.isAndroid) {
      if (kDebugMode) {
        debugPrint('[AdService] Ads not supported on this platform');
      }
      return;
    }

    await MobileAds.instance.initialize();
    _isInitialized = true;

    if (kDebugMode) {
      debugPrint('[AdService] MobileAds initialized');
    }
  }

  /// 広告がサポートされているかどうか
  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  /// バナー広告ユニットID
  String get bannerAdUnitId {
    // テスト広告ID（Google公式）
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/9214589741';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2435281174';
    }
    throw UnsupportedError('Unsupported platform for ads');
  }

  /// Adaptive Bannerサイズを取得
  Future<AnchoredAdaptiveBannerAdSize?> getAdaptiveBannerSize(
    double width,
  ) async {
    return await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      width.truncate(),
    );
  }

  /// バナー広告をロード
  Future<BannerAd?> loadBannerAd({
    required double width,
    required void Function(Ad) onAdLoaded,
    required void Function(Ad, LoadAdError) onAdFailedToLoad,
  }) async {
    if (!isSupported) return null;

    final adSize = await getAdaptiveBannerSize(width);
    if (adSize == null) {
      if (kDebugMode) {
        debugPrint('[AdService] Failed to get adaptive banner size');
      }
      return null;
    }

    final bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      size: adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
        onAdOpened: (ad) {
          if (kDebugMode) {
            debugPrint('[AdService] Banner ad opened');
          }
        },
        onAdClosed: (ad) {
          if (kDebugMode) {
            debugPrint('[AdService] Banner ad closed');
          }
        },
      ),
    );

    await bannerAd.load();
    return bannerAd;
  }
}
