import 'package:supabase_flutter/supabase_flutter.dart';

import 'edge_function_video_provider.dart' show EdgeFunctionInvoker;

/// One poll's outcome, reported by the `video-status` Edge Function.
class VideoStatusResult {
  const VideoStatusResult._({
    required this.status,
    this.videoUrl,
    this.videoStoragePath,
    this.thumbnailUrl,
    this.thumbnailStoragePath,
    this.metadata = const {},
    this.error,
  });

  const VideoStatusResult.processing() : this._(status: 'processing');

  const VideoStatusResult.completed({
    required String videoUrl,
    required String videoStoragePath,
    String? thumbnailUrl,
    String? thumbnailStoragePath,
    Map<String, dynamic> metadata = const {},
  }) : this._(
          status: 'completed',
          videoUrl: videoUrl,
          videoStoragePath: videoStoragePath,
          thumbnailUrl: thumbnailUrl,
          thumbnailStoragePath: thumbnailStoragePath,
          metadata: metadata,
        );

  const VideoStatusResult.failed(String error) : this._(status: 'failed', error: error);

  final String status; // 'processing' | 'completed' | 'failed'
  final String? videoUrl;
  final String? videoStoragePath;
  final String? thumbnailUrl;
  final String? thumbnailStoragePath;
  final Map<String, dynamic> metadata;
  final String? error;

  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}

/// Wraps calls to the `video-status` Edge Function - polled repeatedly (by
/// [VideoPollingController]) while a video generation is processing. See
/// docs/video-generation.md for the full async architecture.
class VideoStatusChecker {
  VideoStatusChecker(SupabaseClient client) : _invoke = client.functions.invoke;

  /// Test-only constructor - injects a fake invoker instead of a real
  /// [SupabaseClient].
  VideoStatusChecker.withInvoker(this._invoke);

  final EdgeFunctionInvoker _invoke;

  static const String functionName = 'video-status';

  Future<VideoStatusResult> check({
    required String generationId,
    required String jobId,
  }) async {
    try {
      final response = await _invoke(
        functionName,
        body: {'generationId': generationId, 'jobId': jobId},
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        return VideoStatusResult.failed(_messageFrom(data));
      }

      switch (data['status'] as String?) {
        case 'completed':
          final video = (data['video'] as Map?)?.cast<String, dynamic>();
          final thumbnail = (data['thumbnail'] as Map?)?.cast<String, dynamic>();
          if (video == null || video['signedUrl'] == null) {
            return const VideoStatusResult.failed(
              'The video generation service did not return a video.',
            );
          }
          return VideoStatusResult.completed(
            videoUrl: video['signedUrl'] as String,
            videoStoragePath: video['storagePath'] as String,
            thumbnailUrl: thumbnail?['signedUrl'] as String?,
            thumbnailStoragePath: thumbnail?['storagePath'] as String?,
            metadata: (data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
        case 'failed':
          return VideoStatusResult.failed(
            data['error'] as String? ?? 'Video generation failed.',
          );
        default:
          return const VideoStatusResult.processing();
      }
    } on FunctionException catch (e) {
      return VideoStatusResult.failed(_messageFrom(e.details));
    } catch (_) {
      // A transient network hiccup while polling shouldn't fail the whole
      // generation - report "still processing" and let the next poll (or
      // the polling controller's own attempt limit) decide.
      return const VideoStatusResult.processing();
    }
  }

  String _messageFrom(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong while checking your video. Please try again.';
  }
}
