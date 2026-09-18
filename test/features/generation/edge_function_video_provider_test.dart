import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/features/generation/services/ai_provider.dart';
import 'package:createai_studio/features/generation/services/edge_function_video_provider.dart';

void main() {
  group('EdgeFunctionVideoProvider', () {
    test('starts a job and returns a pending result carrying the jobId', () async {
      final provider = EdgeFunctionVideoProvider.withInvoker((name, {body}) async {
        expect(name, 'generate-video');
        expect((body as Map)['prompt'], 'a cinematic pharmacy ad');
        expect(body['referenceImagePath'], isNull);
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'status': 'processing',
            'jobId': 'mock:1700000000000:16:9',
            'provider': 'mock',
            'model': 'mock-video-v1',
            'metadata': {'aspectRatio': '16:9', 'resolution': '720p'},
          },
        );
      });

      final result = await provider.generate(
        const AIGenerationRequest(prompt: 'a cinematic pharmacy ad'),
      );

      expect(result.isPending, isTrue);
      expect(result.metadata['jobId'], 'mock:1700000000000:16:9');
      expect(result.metadata['provider'], 'mock');
      expect(result.metadata['model'], 'mock-video-v1');
      expect(result.metadata['aspectRatio'], '16:9');
    });

    test('forwards the first attachment as referenceImagePath', () async {
      Map<dynamic, dynamic>? capturedBody;
      final provider = EdgeFunctionVideoProvider.withInvoker((name, {body}) async {
        capturedBody = body as Map;
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'status': 'processing',
            'jobId': 'job-1',
            'provider': 'stability',
            'model': 'stable-video-diffusion',
            'metadata': {},
          },
        );
      });

      await provider.generate(
        const AIGenerationRequest(
          prompt: '',
          attachmentUrls: ['user-1/uploads/reference.png'],
        ),
      );

      expect(capturedBody!['referenceImagePath'], 'user-1/uploads/reference.png');
    });

    test('throws a GenerationException with the server message on FunctionException', () {
      final provider = EdgeFunctionVideoProvider.withInvoker((name, {body}) async {
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
        () => provider.generate(const AIGenerationRequest(prompt: 'a video')),
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
      final provider = EdgeFunctionVideoProvider.withInvoker((name, {body}) async {
        throw Exception('socket closed');
      });

      expect(
        () => provider.generate(const AIGenerationRequest(prompt: 'a video')),
        throwsA(isA<GenerationException>()),
      );
    });

    test('throws when the response reports success but has no jobId', () {
      final provider = EdgeFunctionVideoProvider.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {'success': true},
        );
      });

      expect(
        () => provider.generate(const AIGenerationRequest(prompt: 'a video')),
        throwsA(isA<GenerationException>()),
      );
    });
  });
}
