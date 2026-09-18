import 'package:equatable/equatable.dart';

/// The server-trusted cost of one generation, read from the `credit_costs`
/// table. Flutter uses this ONLY to display "Generate Video - 5 credits"
/// before submitting - the actual charge is always recomputed and enforced
/// server-side by the generate-* Edge Functions, which never trust a cost
/// supplied by the client. See docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
class CreditCost extends Equatable {
  const CreditCost({
    required this.generationType,
    required this.cost,
    required this.active,
    this.variant,
  });

  final String generationType;
  final String? variant;
  final int cost;
  final bool active;

  factory CreditCost.fromJson(Map<String, dynamic> json) => CreditCost(
        generationType: json['generation_type'] as String,
        variant: json['variant'] as String?,
        cost: (json['cost'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [generationType, variant, cost, active];
}
