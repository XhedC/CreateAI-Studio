import 'package:equatable/equatable.dart';

import 'funnel_schema.dart';
import 'funnel_schema_validator.dart';

/// The sanitized, publicly-visible shape of a published funnel - exactly
/// (and only) what `get_public_funnel(slug)` returns. Deliberately a
/// separate, narrower type from [FunnelModel]: it can never carry `id`,
/// `userId`, `projectId`, `generationId`, `status`, or the draft `content`,
/// because those simply aren't columns the RPC ever selects. See
/// docs/PHASE_7_PUBLISHING.md "Public data access".
class PublicFunnelView extends Equatable {
  const PublicFunnelView({
    required this.name,
    required this.funnelType,
    required this.content,
    required this.publicSlug,
    required this.publishedAt,
    required this.publishedVersion,
  });

  final String name;
  final String funnelType;
  final FunnelSchema content;
  final String publicSlug;
  final DateTime publishedAt;
  final int publishedVersion;

  factory PublicFunnelView.fromJson(Map<String, dynamic> json) {
    final funnelType = json['funnelType'] as String? ?? 'custom';
    final name = json['name'] as String? ?? 'Untitled';
    final rawContent = (json['content'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PublicFunnelView(
      name: name,
      funnelType: funnelType,
      content: FunnelSchemaValidator.validate(
        rawContent,
        fallbackName: name,
        fallbackType: funnelType,
      ),
      publicSlug: json['publicSlug'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      publishedVersion: (json['publishedVersion'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [name, funnelType, content, publicSlug, publishedAt, publishedVersion];
}
