import 'package:equatable/equatable.dart';

class GenerationModel extends Equatable {
  const GenerationModel({
    required this.id,
    required this.userId,
    this.projectId,
    required this.generationType,
    required this.prompt,
    required this.status,
    this.provider,
    this.model,
    this.resultText,
    this.resultUrl,
    this.thumbnailUrl,
    this.metadata = const {},
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String userId;
  final String? projectId;
  final String generationType;
  final String prompt;
  final String status;
  final String? provider;
  final String? model;
  final String? resultText;
  final String? resultUrl;
  final String? thumbnailUrl;
  final Map<String, dynamic> metadata;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  factory GenerationModel.fromJson(Map<String, dynamic> json) => GenerationModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        projectId: json['project_id'] as String?,
        generationType: json['generation_type'] as String,
        prompt: json['prompt'] as String,
        status: json['status'] as String,
        provider: json['provider'] as String?,
        model: json['model'] as String?,
        resultText: json['result_text'] as String?,
        resultUrl: json['result_url'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
        errorMessage: json['error_message'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String),
      );

  GenerationModel copyWith({
    String? status,
    String? resultText,
    String? resultUrl,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
    String? errorMessage,
    DateTime? completedAt,
  }) =>
      GenerationModel(
        id: id,
        userId: userId,
        projectId: projectId,
        generationType: generationType,
        prompt: prompt,
        status: status ?? this.status,
        provider: provider,
        model: model,
        resultText: resultText ?? this.resultText,
        resultUrl: resultUrl ?? this.resultUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        metadata: metadata ?? this.metadata,
        errorMessage: errorMessage ?? this.errorMessage,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  @override
  List<Object?> get props => [
        id,
        userId,
        projectId,
        generationType,
        prompt,
        status,
        provider,
        model,
        resultText,
        resultUrl,
        thumbnailUrl,
        metadata,
        errorMessage,
        createdAt,
        completedAt,
      ];
}
