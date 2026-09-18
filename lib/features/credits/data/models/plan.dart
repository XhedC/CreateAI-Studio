import 'package:equatable/equatable.dart';

/// A subscription plan tier, entirely DB-driven (`plans` table) - per
/// docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md, plan names/limits/pricing must
/// never be hardcoded in Flutter so they can change without an app release.
/// `priceDisplay` is deliberately free text ("Free", "Pricing coming soon")
/// rather than a cents amount - no final pricing exists yet.
class Plan extends Equatable {
  const Plan({
    required this.code,
    required this.name,
    required this.monthlyCredits,
    required this.priceDisplay,
    required this.active,
    this.description,
    this.features = const {},
  });

  final String code;
  final String name;
  final int monthlyCredits;
  final String priceDisplay;
  final bool active;
  final String? description;
  final Map<String, dynamic> features;

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
        code: json['code'] as String,
        name: json['name'] as String? ?? json['code'] as String,
        monthlyCredits: (json['monthly_credits'] as num?)?.toInt() ?? 0,
        priceDisplay: json['price_display'] as String? ?? 'Pricing coming soon',
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
        features: (json['features'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  @override
  List<Object?> get props => [
        code,
        name,
        monthlyCredits,
        priceDisplay,
        active,
        description,
        features,
      ];
}
