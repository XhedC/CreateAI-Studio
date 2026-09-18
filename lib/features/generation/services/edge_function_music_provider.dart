import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/creation_type.dart';
import '../../../core/errors/app_exception.dart';
import 'ai_provider.dart';

/// Mirrors [EdgeFunctionInvoker] in edge_function_image_provider.dart -
/// injectable so this provider can be unit tested without a real network
/// call or a mocked [SupabaseClient].
typedef EdgeFunctionInvoker = Future<FunctionResponse> Function(
  String functionName, {
  Object? body,
});

/// Real AI music provider: calls the `generate-music` Supabase Edge
/// Function instead of any AI vendor SDK directly, so the music provider's
/// secret key never has to exist in this app - see
/// docs/music-generation.md. Mirrors [EdgeFunctionImageProvider] exactly;
/// see that class's docs for the overall pattern.
class EdgeFunctionMusicProvider implements MusicAIProvider {
  EdgeFunctionMusicProvider(SupabaseClient client)
      : _invoke = client.functions.invoke;

  /// Test-only constructor - injects a fake invoker instead of a real
  /// [SupabaseClient].
  EdgeFunctionMusicProvider.withInvoker(this._invoke);

  final EdgeFunctionInvoker _invoke;

  static const String functionName = 'generate-music';

  @override
  CreationType get type => CreationType.music;

  // Placeholders only - the real provider/model (mock vs. stability) isn't
  // known until the Edge Function responds. GenerationOrchestrator prefers
  // metadata.provider/metadata.model over these when present.
  @override
  String get providerName => 'unknown';
  @override
  String get modelName => 'unknown';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    final lyrics = request.options['lyrics'] as String?;
    final settings = Map<String, dynamic>.from(request.options)..remove('lyrics');

    final FunctionResponse response;
    try {
      response = await _invoke(
        functionName,
        body: {
          'prompt': request.prompt,
          'lyrics': lyrics,
          'settings': settings,
        },
      );
    } on FunctionException catch (e) {
      throw GenerationException(message: _messageFrom(e.details));
    } catch (_) {
      throw const GenerationException(
        message: 'Could not reach the music generation service. Please try again.',
      );
    }

    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw GenerationException(message: _messageFrom(data));
    }

    final audio = data['audio'] as Map?;
    if (audio == null || audio['signedUrl'] == null) {
      throw const GenerationException(
        message: 'The music generation service did not return any audio.',
      );
    }

    final metadata = <String, dynamic>{
      ...(data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      'provider': data['provider'],
      'model': data['model'],
      'storagePath': audio['storagePath'],
      'mimeType': audio['mimeType'],
      'durationSeconds': audio['durationSeconds'],
    };

    return AIGenerationResult(
      resultUrl: audio['signedUrl'] as String?,
      metadata: metadata,
    );
  }

  String _messageFrom(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong while generating your music. Please try again.';
  }
}
