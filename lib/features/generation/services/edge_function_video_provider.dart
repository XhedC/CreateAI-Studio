import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/creation_type.dart';
import '../../../core/errors/app_exception.dart';
import 'ai_provider.dart';

/// Mirrors [EdgeFunctionInvoker] in edge_function_image_provider.dart and
/// edge_function_music_provider.dart - injectable so this provider can be
/// unit tested without a real network call or a mocked [SupabaseClient].
typedef EdgeFunctionInvoker = Future<FunctionResponse> Function(
  String functionName, {
  Object? body,
});

/// Real AI video provider: calls the `generate-video` Supabase Edge
/// Function to *start* a job - it never waits for the video itself, since
/// video generation is genuinely asynchronous (unlike the image/music
/// providers, which call an Edge Function that returns the final result in
/// one round trip). See docs/video-generation.md.
///
/// Returns an [AIGenerationResult] with `isPending: true` and the provider's
/// job id in `metadata['jobId']` - [GenerationOrchestrator] persists that as
/// `status: processing` rather than `completed`. A separate
/// [VideoStatusPoller] (video_status_checker.dart) takes over from there.
class EdgeFunctionVideoProvider implements VideoAIProvider {
  EdgeFunctionVideoProvider(SupabaseClient client)
      : _invoke = client.functions.invoke;

  /// Test-only constructor - injects a fake invoker instead of a real
  /// [SupabaseClient].
  EdgeFunctionVideoProvider.withInvoker(this._invoke);

  final EdgeFunctionInvoker _invoke;

  static const String functionName = 'generate-video';

  @override
  CreationType get type => CreationType.video;

  // Placeholders only - see EdgeFunctionImageProvider's identical comment.
  @override
  String get providerName => 'unknown';
  @override
  String get modelName => 'unknown';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    final FunctionResponse response;
    try {
      response = await _invoke(
        functionName,
        body: {
          'prompt': request.prompt,
          'referenceImagePath':
              request.attachmentUrls.isNotEmpty ? request.attachmentUrls.first : null,
          'settings': request.options,
        },
      );
    } on FunctionException catch (e) {
      throw GenerationException(message: _messageFrom(e.details));
    } catch (_) {
      throw const GenerationException(
        message: 'Could not reach the video generation service. Please try again.',
      );
    }

    final data = response.data;
    if (data is! Map || data['success'] != true || data['jobId'] == null) {
      throw GenerationException(message: _messageFrom(data));
    }

    return AIGenerationResult(
      isPending: true,
      metadata: {
        ...(data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
        'provider': data['provider'],
        'model': data['model'],
        'jobId': data['jobId'],
      },
    );
  }

  String _messageFrom(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong while starting your video. Please try again.';
  }
}
