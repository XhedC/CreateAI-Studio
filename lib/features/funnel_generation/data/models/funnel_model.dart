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
    );
  }

  FunnelModel copyWith({String? name, String? funnelType, String? status, FunnelSchema? content}) =>
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
      ];
}
