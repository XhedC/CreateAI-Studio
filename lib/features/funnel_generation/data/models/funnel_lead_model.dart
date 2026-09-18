import 'package:equatable/equatable.dart';

/// A row from `funnel_leads` - a visitor submission captured by a funnel's
/// Lead Form section. See docs/funnel-generation.md for why `userId` here
/// is the funnel OWNER, not the submitting visitor.
class FunnelLeadModel extends Equatable {
  const FunnelLeadModel({
    required this.id,
    required this.funnelId,
    required this.userId,
    this.name,
    this.email,
    this.phone,
    this.message,
    required this.createdAt,
  });

  final String id;
  final String funnelId;
  final String userId;
  final String? name;
  final String? email;
  final String? phone;
  final String? message;
  final DateTime createdAt;

  factory FunnelLeadModel.fromJson(Map<String, dynamic> json) => FunnelLeadModel(
        id: json['id'] as String,
        funnelId: json['funnel_id'] as String,
        userId: json['user_id'] as String,
        name: json['name'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        message: json['message'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [id, funnelId, userId, name, email, phone, message, createdAt];
}
