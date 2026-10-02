import 'package:equatable/equatable.dart';

enum SegmentStatus {
  pending('pending'),
  processing('processing'),
  completed('completed'),
  failed('failed');

  const SegmentStatus(this.value);
  final String value;

  static SegmentStatus fromValue(String value) => SegmentStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => SegmentStatus.pending,
      );
}

enum SegmentInputType {
  text('text'),
  photo('photo'),
  voice('voice');

  const SegmentInputType(this.value);
  final String value;

  static SegmentInputType fromValue(String value) => SegmentInputType.values.firstWhere(
        (s) => s.value == value,
        orElse: () => SegmentInputType.text,
      );
}

class VideoSegmentModel extends Equatable {
  const VideoSegmentModel({
    required this.id,
    required this.storyId,
    required this.userId,
    required this.orderIndex,
    required this.inputType,
    required this.prompt,
    this.photoUrl,
    this.voiceUrl,
    required this.durationSeconds,
    required this.status,
    this.videoUrl,
    this.thumbnailUrl,
    this.generationId,
    this.metadata = const {},
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String storyId;
  final String userId;
  final int orderIndex;
  final SegmentInputType inputType;
  final String prompt;
  final String? photoUrl;
  final String? voiceUrl;
  final int durationSeconds;
  final SegmentStatus status;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? generationId;
  final Map<String, dynamic> metadata;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get isCompleted => status == SegmentStatus.completed;
  bool get isFailed => status == SegmentStatus.failed;
  bool get isProcessing => status == SegmentStatus.processing;

  factory VideoSegmentModel.fromJson(Map<String, dynamic> json) => VideoSegmentModel(
        id: json['id'] as String,
        storyId: json['story_id'] as String,
        userId: json['user_id'] as String,
        orderIndex: json['order_index'] as int,
        inputType: SegmentInputType.fromValue(json['input_type'] as String),
        prompt: json['prompt'] as String,
        photoUrl: json['photo_url'] as String?,
        voiceUrl: json['voice_url'] as String?,
        durationSeconds: json['duration_seconds'] as int,
        status: SegmentStatus.fromValue(json['status'] as String),
        videoUrl: json['video_url'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        generationId: json['generation_id'] as String?,
        metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
        errorMessage: json['error_message'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'story_id': storyId,
        'user_id': userId,
        'order_index': orderIndex,
        'input_type': inputType.value,
        'prompt': prompt,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (voiceUrl != null) 'voice_url': voiceUrl,
        'duration_seconds': durationSeconds,
        'status': status.value,
        if (generationId != null) 'generation_id': generationId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  VideoSegmentModel copyWith({
    int? orderIndex,
    String? prompt,
    String? photoUrl,
    String? voiceUrl,
    int? durationSeconds,
    SegmentStatus? status,
    String? videoUrl,
    String? thumbnailUrl,
    String? generationId,
    Map<String, dynamic>? metadata,
    String? errorMessage,
    DateTime? completedAt,
  }) =>
      VideoSegmentModel(
        id: id,
        storyId: storyId,
        userId: userId,
        orderIndex: orderIndex ?? this.orderIndex,
        inputType: inputType,
        prompt: prompt ?? this.prompt,
        photoUrl: photoUrl ?? this.photoUrl,
        voiceUrl: voiceUrl ?? this.voiceUrl,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        status: status ?? this.status,
        videoUrl: videoUrl ?? this.videoUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        generationId: generationId ?? this.generationId,
        metadata: metadata ?? this.metadata,
        errorMessage: errorMessage ?? this.errorMessage,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  @override
  List<Object?> get props => [
        id, storyId, userId, orderIndex, inputType, prompt, photoUrl, voiceUrl,
        durationSeconds, status, videoUrl, thumbnailUrl, generationId,
        metadata, errorMessage, createdAt, completedAt,
      ];
}
