import 'package:equatable/equatable.dart';

import 'funnel_schema.dart';
import 'funnel_schema_validator.dart';

/// A row from the `funnels` table. `content` is always a validated
/// [FunnelSchema] - see [FunnelSchemaValidator.validate], applied in
/// [fromJson] so nothing malformed ever reaches the UI.
class FunnelModel extends Equatable {
  const FunnelModel({
    required this.id,
    required this.userId,
    this.projectId,
    required this.generationId,
    required this.name,
    this.description,
    required this.funnelType,
    required this.status,
    required this.schemaVersion,
    required this.content,
    this.thumbnailUrl,
    required this.createdAt,
    required this.updatedAt,
    this.published = false,
    this.publishedAt,
    this.unpublishedAt,
    this.publicSlug,
    this.publishedVersion = 0,
  });

  final String id;
  final String userId;
  final String? projectId;
  final String generationId;
  final String name;
  final String? description;
  final String funnelType;
  final String status;
  final int schemaVersion;
  final FunnelSchema content;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this funnel currently has a live public page - orthogonal to
  /// [status] (draft/archived). See docs/PHASE_7_PUBLISHING.md.
  final bool published;
  final DateTime? publishedAt;
  final DateTime? unpublishedAt;

  /// Stable once assigned - never regenerated across unpublish/republish.
  final String? publicSlug;

  /// Incremented on every successful publish/republish.
  final int publishedVersion;

  /// True once the draft has been edited (`updated_at` bumped) since the
  /// last publish - i.e. the live public page no longer reflects the
  /// current draft. Never true for a never-published funnel.
  bool get hasUnpublishedChanges =>
      published && publishedAt != null && updatedAt.isAfter(publishedAt!);

  factory FunnelModel.fromJson(Map<String, dynamic> json) {
    final rawContent = (json['content'] as Map?)?.cast<String, dynamic>() ?? const {};
    final funnelType = json['funnel_type'] as String? ?? 'custom';
    return FunnelModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      projectId: json['project_id'] as String?,
      generationId: json['generation_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      funnelType: funnelType,
      status: json['status'] as String? ?? 'draft',
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      content: FunnelSchemaValidator.validate(
        rawContent,
        fallbackName: json['name'] as String? ?? 'Untitled Funnel',
        fallbackType: funnelType,
      ),
      thumbnailUrl: json['thumbnail_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      published: json['published'] as bool? ?? false,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      unpublishedAt: json['unpublished_at'] != null
          ? DateTime.parse(json['unpublished_at'] as String)
          : null,
      publicSlug: json['public_slug'] as String?,
      publishedVersion: (json['published_version'] as num?)?.toInt() ?? 0,
    );
  }

  FunnelModel copyWith({
    String? name,
    String? funnelType,
    String? status,
    FunnelSchema? content,
    bool? published,
    DateTime? publishedAt,
    DateTime? unpublishedAt,
    String? publicSlug,
    int? publishedVersion,
  }) =>
      FunnelModel(
        id: id,
        userId: userId,
        projectId: projectId,
        generationId: generationId,
        name: name ?? this.name,
        description: description,
        funnelType: funnelType ?? this.funnelType,
        status: status ?? this.status,
        schemaVersion: schemaVersion,
        content: content ?? this.content,
        thumbnailUrl: thumbnailUrl,
        createdAt: createdAt,
        updatedAt: updatedAt,
        published: published ?? this.published,
        publishedAt: publishedAt ?? this.publishedAt,
        unpublishedAt: unpublishedAt ?? this.unpublishedAt,
        publicSlug: publicSlug ?? this.publicSlug,
        publishedVersion: publishedVersion ?? this.publishedVersion,
      );

  @override
  List<Object?> get props => [
        id,
        userId,
        projectId,
        generationId,
        name,
        description,
        funnelType,
        status,
        schemaVersion,
        content,
        thumbnailUrl,
        createdAt,
        updatedAt,
        published,
        publishedAt,
        unpublishedAt,
        publicSlug,
        publishedVersion,
      ];
}
