import 'package:flutter/material.dart';
import 'package:world_visit_app/app/ads/ad_service.dart';
import 'package:world_visit_app/app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AdMobの初期化
  await AdService.instance.initialize();

  runApp(const WorldVisitApp());
}
