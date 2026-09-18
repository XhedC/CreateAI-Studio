import 'package:equatable/equatable.dart';

class GenerationFileModel extends Equatable {
  const GenerationFileModel({
    required this.id,
    required this.generationId,
    required this.userId,
    required this.fileName,
    required this.fileType,
    required this.mimeType,
    required this.storagePath,
    this.fileUrl,
    this.fileSize,
    required this.createdAt,
  });

  final String id;
  final String generationId;
  final String userId;
  final String fileName;
  final String fileType;
  final String mimeType;
  final String storagePath;
  final String? fileUrl;
  final int? fileSize;
  final DateTime createdAt;

  factory GenerationFileModel.fromJson(Map<String, dynamic> json) =>
      GenerationFileModel(
        id: json['id'] as String,
        generationId: json['generation_id'] as String,
        userId: json['user_id'] as String,
        fileName: json['file_name'] as String,
        fileType: json['file_type'] as String,
        mimeType: json['mime_type'] as String,
        storagePath: json['storage_path'] as String,
        fileUrl: json['file_url'] as String?,
        fileSize: json['file_size'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        generationId,
        userId,
        fileName,
        fileType,
        mimeType,
        storagePath,
        fileUrl,
        fileSize,
        createdAt,
      ];
}
