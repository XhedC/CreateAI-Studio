import 'package:equatable/equatable.dart';

/// One row of the auditable credit ledger (`credit_transactions`). Every
/// balance change (monthly grant, generation charge, refund, ...) is
/// recorded here by the backend RPC functions - Flutter only ever reads
/// this table, never writes to it. See docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
class CreditTransaction extends Equatable {
  const CreditTransaction({
    required this.id,
    required this.amount,
    required this.transactionType,
    required this.createdAt,
    this.description,
    this.referenceId,
    this.referenceType,
    this.balanceAfter,
  });

  final String id;
  final int amount;
  final String transactionType;
  final String? description;
  final String? referenceId;
  final String? referenceType;
  final int? balanceAfter;
  final DateTime createdAt;

  bool get isCredit => amount > 0;

  factory CreditTransaction.fromJson(Map<String, dynamic> json) => CreditTransaction(
        id: json['id'] as String,
        amount: (json['amount'] as num).toInt(),
        transactionType: json['transaction_type'] as String,
        description: json['description'] as String?,
        referenceId: json['reference_id'] as String?,
        referenceType: json['reference_type'] as String?,
        balanceAfter: (json['balance_after'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        amount,
        transactionType,
        description,
        referenceId,
        referenceType,
        balanceAfter,
        createdAt,
      ];
}
