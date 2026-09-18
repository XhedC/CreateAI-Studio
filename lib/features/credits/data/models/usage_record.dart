import 'package:equatable/equatable.dart';

/// One billable generation event (`usage_records` - the detail ledger the
/// Usage Dashboard aggregates from). Distinct from [CreditTransaction],
/// which records balance changes; this records what was generated.
class UsageRecord extends Equatable {
  const UsageRecord({
    required this.id,
    required this.generationType,
    required this.creditsConsumed,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String generationType;
  final int creditsConsumed;
  final String status;
  final DateTime createdAt;

  factory UsageRecord.fromJson(Map<String, dynamic> json) => UsageRecord(
        id: json['id'] as String,
        generationType: json['generation_type'] as String,
        creditsConsumed: (json['credits_consumed'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'processing',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [id, generationType, creditsConsumed, status, createdAt];
}
