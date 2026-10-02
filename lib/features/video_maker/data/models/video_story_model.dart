import 'package:equatable/equatable.dart';

import 'video_segment_model.dart';

enum StoryStatus {
  draft('draft'),
  processing('processing'),
  completed('completed'),
  exported('exported');

  const StoryStatus(this.value);
  final String value;

  static StoryStatus fromValue(String value) => StoryStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => StoryStatus.draft,
      );
}

class VideoStoryModel extends Equatable {
  const VideoStoryModel({
    required this.id,
    required this.userId,
    this.projectId,
    required this.title,
    required this.aspectRatio,
    required this.quality,
    required this.style,
    required this.fps,
    required this.status,
    this.finalVideoUrl,
    this.thumbnailUrl,
    this.metadata = const {},
    required this.createdAt,
    this.updatedAt,
    this.segments = const [],
  });

  final String id;
  final String userId;
  final String? projectId;
  final String title;
  final String aspectRatio;
  final String quality;
  final String style;
  final int fps;
  final StoryStatus status;
  final String? finalVideoUrl;
  final String? thumbnailUrl;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<VideoSegmentModel> segments;

  int get totalDurationSeconds =>
      segments.fold(0, (sum, s) => sum + s.durationSeconds);

  int get completedSegments =>
      segments.where((s) => s.isCompleted).length;

  bool get allSegmentsCompleted =>
      segments.isNotEmpty && segments.every((s) => s.isCompleted);

  bool get hasProcessingSegments =>
      segments.any((s) => s.isProcessing);

  factory VideoStoryModel.fromJson(Map<String, dynamic> json) {
    final segmentsJson = json['video_segments'] as List?;
    return VideoStoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      projectId: json['project_id'] as String?,
      title: json['title'] as String,
      aspectRatio: json['aspect_ratio'] as String,
      quality: json['quality'] as String,
      style: json['style'] as String,
      fps: json['fps'] as int? ?? 24,
      status: StoryStatus.fromValue(json['status'] as String),
      finalVideoUrl: json['final_video_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      segments: segmentsJson
              ?.map((s) => VideoSegmentModel.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        if (projectId != null) 'project_id': projectId,
        'title': title,
        'aspect_ratio': aspectRatio,
        'quality': quality,
        'style': style,
        'fps': fps,
        'status': status.value,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  VideoStoryModel copyWith({
    String? title,
    StoryStatus? status,
    String? finalVideoUrl,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
    DateTime? updatedAt,
    List<VideoSegmentModel>? segments,
  }) =>
      VideoStoryModel(
        id: id,
        userId: userId,
        projectId: projectId,
        title: title ?? this.title,
        aspectRatio: aspectRatio,
        quality: quality,
        style: style,
        fps: fps,
        status: status ?? this.status,
        finalVideoUrl: finalVideoUrl ?? this.finalVideoUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        metadata: metadata ?? this.metadata,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        segments: segments ?? this.segments,
      );

  @override
  List<Object?> get props => [
        id, userId, projectId, title, aspectRatio, quality, style, fps,
        status, finalVideoUrl, thumbnailUrl, metadata, createdAt, updatedAt,
        segments,
      ];
}
