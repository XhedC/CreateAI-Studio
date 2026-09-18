import 'package:equatable/equatable.dart';

/// Placeholder credit/subscription summary shown on Home and Profile until
/// the real billing/credits phase is implemented. Backed by the
/// `subscriptions` table (one free-plan row is created for every new user by
/// the `handle_new_user` database trigger).
class CreditSummary extends Equatable {
  const CreditSummary({
    required this.planName,
    required this.creditsLimit,
    required this.creditsUsed,
  });

  final String planName;
  final int creditsLimit;
  final int creditsUsed;

  int get creditsRemaining => (creditsLimit - creditsUsed).clamp(0, creditsLimit);

  static const CreditSummary fallback = CreditSummary(
    planName: 'Free',
    creditsLimit: 50,
    creditsUsed: 0,
  );

  factory CreditSummary.fromJson(Map<String, dynamic> json) => CreditSummary(
        planName: json['plan_name'] as String? ?? 'Free',
        creditsLimit: (json['credits_limit'] as num?)?.toInt() ?? 50,
        creditsUsed: (json['credits_used'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [planName, creditsLimit, creditsUsed];
}
