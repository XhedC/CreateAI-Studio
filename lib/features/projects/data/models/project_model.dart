import 'package:equatable/equatable.dart';

class ProjectModel extends Equatable {
  const ProjectModel({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    required this.projectType,
    this.thumbnailUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? description;
  final String projectType;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProjectModel.fromJson(Map<String, dynamic> json) => ProjectModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        projectType: json['project_type'] as String? ?? 'general',
        thumbnailUrl: json['thumbnail_url'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        'name': name,
        if (description != null) 'description': description,
        'project_type': projectType,
      };

  ProjectModel copyWith({
    String? name,
    String? description,
    String? thumbnailUrl,
  }) =>
      ProjectModel(
        id: id,
        userId: userId,
        name: name ?? this.name,
        description: description ?? this.description,
        projectType: projectType,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        userId,
        name,
        description,
        projectType,
        thumbnailUrl,
        createdAt,
        updatedAt,
      ];
}
