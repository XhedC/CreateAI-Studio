import 'package:equatable/equatable.dart';

/// Credit/subscription summary shown on Home, Profile, and the Usage
/// Dashboard. Backed by the `subscriptions` table (one free-plan row is
/// created for every new user by the `handle_new_user` database trigger).
///
/// The backend (`subscriptions.credits_limit`/`credits_used`, mutated only
/// via the Phase 6 SECURITY DEFINER RPC functions) is the sole source of
/// truth for actual balance - this model only displays what the server
/// already computed. See docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
class CreditSummary extends Equatable {
  const CreditSummary({
    required this.planName,
    required this.creditsLimit,
    required this.creditsUsed,
    this.planCode,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.lifetimeCreditsEarned = 0,
    this.lifetimeCreditsUsed = 0,
  });

  final String planName;
  final int creditsLimit;
  final int creditsUsed;

  /// The plan's stable machine code (`free`/`pro`/`business`) - distinct
  /// from [planName], which historically stored the same lowercase value
  /// but is display text, not an identifier to branch logic on.
  final String? planCode;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final int lifetimeCreditsEarned;
  final int lifetimeCreditsUsed;

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
        planCode: json['plan_name'] as String?,
        currentPeriodStart: json['current_period_start'] != null
            ? DateTime.tryParse(json['current_period_start'] as String)
            : null,
        currentPeriodEnd: json['current_period_end'] != null
            ? DateTime.tryParse(json['current_period_end'] as String)
            : null,
        cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
        lifetimeCreditsEarned: (json['lifetime_credits_earned'] as num?)?.toInt() ?? 0,
        lifetimeCreditsUsed: (json['lifetime_credits_used'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [
        planName,
        creditsLimit,
        creditsUsed,
        planCode,
        currentPeriodStart,
        currentPeriodEnd,
        cancelAtPeriodEnd,
        lifetimeCreditsEarned,
        lifetimeCreditsUsed,
      ];
}
