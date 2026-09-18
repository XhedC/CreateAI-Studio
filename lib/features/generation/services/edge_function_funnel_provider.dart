import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/creation_type.dart';
import '../../../core/errors/app_exception.dart';
import 'ai_provider.dart';

/// Mirrors [EdgeFunctionInvoker] in edge_function_image_provider.dart and
/// the other Edge Function providers - injectable so this provider can be
/// unit tested without a real network call or a mocked [SupabaseClient].
typedef EdgeFunctionInvoker = Future<FunctionResponse> Function(
  String functionName, {
  Object? body,
});

/// Real AI funnel provider: calls the `generate-funnel` Supabase Edge
/// Function, which calls the configured LLM, validates/corrects its
/// response into a `FunnelSchema`, and stores it in the `funnels` table -
/// see docs/funnel-generation.md.
///
/// Unlike video (genuinely async), this is a single, synchronous round
/// trip like image/music: the Edge Function returns the finished, validated
/// funnel directly.
///
/// A funnel has two independent optional images (a logo and a product/
/// reference image), unlike image/video's single reference image - rather
/// than overload [AIGenerationRequest.attachmentUrls]'s positional-list
/// convention for two different semantic roles, both are passed as
/// distinctly-named keys in [AIGenerationRequest.options]
/// (`logoPath`/`productImagePath`), alongside the business-info fields the
/// Funnel Generator screen collects.
class EdgeFunctionFunnelProvider implements FunnelAIProvider {
  EdgeFunctionFunnelProvider(SupabaseClient client) : _invoke = client.functions.invoke;

  /// Test-only constructor - injects a fake invoker instead of a real
  /// [SupabaseClient].
  EdgeFunctionFunnelProvider.withInvoker(this._invoke);

  final EdgeFunctionInvoker _invoke;

  static const String functionName = 'generate-funnel';

  @override
  CreationType get type => CreationType.funnel;

  // Placeholders only - see EdgeFunctionImageProvider's identical comment.
  @override
  String get providerName => 'unknown';
  @override
  String get modelName => 'unknown';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    final options = request.options;
    final FunctionResponse response;
    try {
      response = await _invoke(
        functionName,
        body: {
          'generationId': request.generationId,
          'prompt': request.prompt,
          'funnelType': options['funnelType'],
          'businessInfo': {
            'businessName': options['businessName'],
            'businessType': options['businessType'],
            'product': options['product'],
            'targetAudience': options['targetAudience'],
            'goal': options['goal'],
            'offer': options['offer'],
            'cta': options['cta'],
          },
          'logoPath': options['logoPath'],
          'productImagePath': options['productImagePath'],
        },
      );
    } on FunctionException catch (e) {
      throw GenerationException(message: _messageFrom(e.details));
    } catch (_) {
      throw const GenerationException(
        message: 'Could not reach the funnel generation service. Please try again.',
      );
    }

    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw GenerationException(message: _messageFrom(data));
    }

    final funnel = (data['funnel'] as Map?)?.cast<String, dynamic>();
    if (funnel == null || data['funnelId'] == null) {
      throw const GenerationException(
        message: 'The funnel generation service did not return a funnel.',
      );
    }
    final theme = (funnel['theme'] as Map?)?.cast<String, dynamic>();

    return AIGenerationResult(
      resultText: funnel['name'] as String?,
      thumbnailUrl: theme?['logoUrl'] as String?,
      metadata: {
        ...(data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
        'provider': data['provider'],
        'model': data['model'],
        'funnelId': data['funnelId'],
      },
    );
  }

  String _messageFrom(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong while generating your funnel. Please try again.';
  }
}
