import 'package:flutter/material.dart';

/// Brand seed color and semantic colors shared by both themes.
class AppColors {
  const AppColors._();

  static const Color seed = Color(0xFF6750F4);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFED6C02);
  static const Color danger = Color(0xFFD32F2F);
  static const Color info = Color(0xFF0288D1);

  // Generation-type accent colors (used by FeatureCard / creation type chips).
  static const Color textType = Color(0xFF6750F4);
  static const Color imageType = Color(0xFFE91E8C);
  static const Color musicType = Color(0xFFFF9800);
  static const Color videoType = Color(0xFF2196F3);
  static const Color funnelType = Color(0xFF00BFA5);
}
