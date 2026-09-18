import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/features/generation/services/ai_provider.dart';
import 'package:createai_studio/features/generation/services/edge_function_funnel_provider.dart';

void main() {
  group('EdgeFunctionFunnelProvider', () {
    test('maps a successful response to an AIGenerationResult', () async {
      final provider = EdgeFunctionFunnelProvider.withInvoker((name, {body}) async {
        expect(name, 'generate-funnel');
        final sentBody = body as Map;
        expect(sentBody['generationId'], 'gen-1');
        expect(sentBody['prompt'], 'a pharmacy landing page');
        expect((sentBody['businessInfo'] as Map)['businessName'], 'CrossCare Pharmacy');

        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'funnelId': 'funnel-1',
            'provider': 'mock',
            'model': 'mock-funnel-v2',
            'funnel': {
              'version': 1,
              'name': 'CrossCare Pharmacy Landing Page',
              'type': 'pharmacy',
              'theme': {'logoUrl': 'https://example.com/logo.png'},
            },
            'metadata': {'sectionsCount': 7},
          },
        );
      });

      final result = await provider.generate(
        const AIGenerationRequest(
          prompt: 'a pharmacy landing page',
          generationId: 'gen-1',
          options: {
            'funnelType': 'pharmacy',
            'businessName': 'CrossCare Pharmacy',
          },
        ),
      );

      expect(result.resultText, 'CrossCare Pharmacy Landing Page');
      expect(result.thumbnailUrl, 'https://example.com/logo.png');
      expect(result.metadata['funnelId'], 'funnel-1');
      expect(result.metadata['provider'], 'mock');
      expect(result.metadata['model'], 'mock-funnel-v2');
      expect(result.metadata['sectionsCount'], 7);
    });

    test('throws a GenerationException with the server message on FunctionException', () {
      final provider = EdgeFunctionFunnelProvider.withInvoker((name, {body}) async {
        throw const FunctionException(
          status: 402,
          details: {
            'success': false,
            'error': "You don't have enough credits for this generation.",
            'code': 'INSUFFICIENT_CREDITS',
          },
        );
      });

      expect(
        () => provider.generate(
          const AIGenerationRequest(prompt: 'a funnel', generationId: 'gen-1'),
        ),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.message,
            'message',
            "You don't have enough credits for this generation.",
          ),
        ),
      );
    });

    test('throws a safe fallback message when the function is unreachable', () {
      final provider = EdgeFunctionFunnelProvider.withInvoker((name, {body}) async {
        throw Exception('socket closed');
      });

      expect(
        () => provider.generate(
          const AIGenerationRequest(prompt: 'a funnel', generationId: 'gen-1'),
        ),
        throwsA(isA<GenerationException>()),
      );
    });

    test('throws when the response reports success but has no funnel', () {
      final provider = EdgeFunctionFunnelProvider.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {'success': true},
        );
      });

      expect(
        () => provider.generate(
          const AIGenerationRequest(prompt: 'a funnel', generationId: 'gen-1'),
        ),
        throwsA(isA<GenerationException>()),
      );
    });
  });
}
