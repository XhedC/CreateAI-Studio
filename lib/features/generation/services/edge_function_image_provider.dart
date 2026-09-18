import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/creation_type.dart';
import '../../../core/errors/app_exception.dart';
import 'ai_provider.dart';

/// Thin, injectable wrapper around [SupabaseClient.functions.invoke] so
/// [EdgeFunctionImageProvider] can be unit tested without a real network
/// call or a mocked [SupabaseClient].
typedef EdgeFunctionInvoker = Future<FunctionResponse> Function(
  String functionName, {
  Object? body,
});

/// Real AI image provider: calls the `generate-image` Supabase Edge
/// Function instead of any AI vendor SDK directly, so the OpenAI (or any
/// other vendor) secret key never has to exist in this app - see
/// docs/image-generation.md.
///
/// This is the "swap the provider" step promised by docs/ai-integration.md:
/// wiring it into [imageAIProviderProvider] is the entire diff needed to
/// move the Image category off the Phase 1 mock.
class EdgeFunctionImageProvider implements ImageAIProvider {
  EdgeFunctionImageProvider(SupabaseClient client)
      : _invoke = client.functions.invoke;

  /// Test-only constructor - injects a fake invoker instead of a real
  /// [SupabaseClient].
  EdgeFunctionImageProvider.withInvoker(this._invoke);

  final EdgeFunctionInvoker _invoke;

  static const String functionName = 'generate-image';

  @override
  CreationType get type => CreationType.image;

  // These are placeholders only - the real values always come back from the
  // Edge Function's response (`metadata.provider`/`metadata.model`), since
  // the backend decides mock vs. a real vendor. See
  // GenerationOrchestrator.generate(), which prefers metadata over these.
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
          'generationId': request.generationId,
          'prompt': request.prompt,
          'referenceImagePath':
              request.attachmentUrls.isNotEmpty ? request.attachmentUrls.first : null,
          'settings': request.options,
        },
      );
    } on FunctionException catch (e) {
      throw GenerationException(message: _messageFrom(e.details), code: _codeFrom(e.details));
    } catch (_) {
      throw const GenerationException(
        message: 'Could not reach the image generation service. Please try again.',
      );
    }

    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw GenerationException(message: _messageFrom(data), code: _codeFrom(data));
    }

    final images = (data['images'] as List? ?? const [])
        .cast<Map<dynamic, dynamic>>();
    if (images.isEmpty) {
      throw const GenerationException(
        message: 'The image generation service did not return any images.',
      );
    }

    final metadata = <String, dynamic>{
      ...(data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      'provider': data['provider'],
      'model': data['model'],
      'storagePath': images.first['storagePath'],
    };

    return AIGenerationResult(
      resultUrl: images.first['signedUrl'] as String?,
      thumbnailUrl: images.first['signedUrl'] as String?,
      metadata: metadata,
      additionalFiles: [
        for (var i = 1; i < images.length; i++)
          GenerationResultFile(
            fileName: 'image-${i + 1}.${_extensionFor(images[i]['mimeType'] as String?)}',
            mimeType: images[i]['mimeType'] as String? ?? 'image/png',
            storagePath: images[i]['storagePath'] as String? ?? '',
            fileUrl: images[i]['signedUrl'] as String?,
            fileSize: (images[i]['fileSize'] as num?)?.toInt(),
          ),
      ],
    );
  }

  String _messageFrom(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong while generating your image. Please try again.';
  }

  String? _codeFrom(Object? details) {
    if (details is Map && details['code'] is String) {
      return details['code'] as String;
    }
    return null;
  }

  String _extensionFor(String? mimeType) {
    if (mimeType == null) return 'png';
    if (mimeType.contains('webp')) return 'webp';
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpg';
    return 'png';
  }
}
