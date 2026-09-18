import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/features/generation/services/ai_provider.dart';
import 'package:createai_studio/features/generation/services/edge_function_music_provider.dart';

void main() {
  group('EdgeFunctionMusicProvider', () {
    test('maps a successful response to an AIGenerationResult', () async {
      final provider = EdgeFunctionMusicProvider.withInvoker((name, {body}) async {
        expect(name, 'generate-music');
        expect((body as Map)['prompt'], 'an uplifting acoustic song');
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'provider': 'mock',
            'model': 'mock-music-v1',
            'audio': {
              'storagePath': 'user-1/generations/req-1/result.wav',
              'signedUrl': 'https://example.com/result.wav',
              'mimeType': 'audio/wav',
              'fileSize': 4096,
              'durationSeconds': 15,
            },
            'metadata': {'genre': 'acoustic', 'mood': 'happy'},
          },
        );
      });

      final result = await provider.generate(
        const AIGenerationRequest(prompt: 'an uplifting acoustic song'),
      );

      expect(result.resultUrl, 'https://example.com/result.wav');
      expect(result.metadata['provider'], 'mock');
      expect(result.metadata['model'], 'mock-music-v1');
      expect(result.metadata['storagePath'], 'user-1/generations/req-1/result.wav');
      expect(result.metadata['durationSeconds'], 15);
    });

    test('splits lyrics out of options and sends it as a top-level field', () async {
      Map<dynamic, dynamic>? capturedBody;
      final provider = EdgeFunctionMusicProvider.withInvoker((name, {body}) async {
        capturedBody = body as Map;
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'provider': 'mock',
            'model': 'mock-music-v1',
            'audio': {
              'storagePath': 'p',
              'signedUrl': 'https://example.com/result.wav',
              'mimeType': 'audio/wav',
            },
            'metadata': {},
          },
        );
      });

      await provider.generate(
        const AIGenerationRequest(
          prompt: 'a song',
          options: {'genre': 'pop', 'lyrics': 'la la la'},
        ),
      );

      expect(capturedBody!['lyrics'], 'la la la');
      expect((capturedBody!['settings'] as Map)['genre'], 'pop');
      expect((capturedBody!['settings'] as Map).containsKey('lyrics'), isFalse);
    });

    test('sends the generationId from the request', () async {
      Map<dynamic, dynamic>? capturedBody;
      final provider = EdgeFunctionMusicProvider.withInvoker((name, {body}) async {
        capturedBody = body as Map;
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'audio': {
              'storagePath': 'p',
              'signedUrl': 'https://example.com/result.wav',
              'mimeType': 'audio/wav',
            },
            'metadata': {},
          },
        );
      });

      await provider.generate(
        const AIGenerationRequest(prompt: 'a song', generationId: 'gen-123'),
      );

      expect(capturedBody!['generationId'], 'gen-123');
    });

    test('throws a GenerationException with the server message on FunctionException', () {
      final provider = EdgeFunctionMusicProvider.withInvoker((name, {body}) async {
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
        () => provider.generate(const AIGenerationRequest(prompt: 'a song')),
        throwsA(
          isA<GenerationException>()
              .having(
                (e) => e.message,
                'message',
                "You don't have enough credits for this generation.",
              )
              .having((e) => e.code, 'code', 'INSUFFICIENT_CREDITS'),
        ),
      );
    });

    test('throws a safe fallback message when the function is unreachable', () {
      final provider = EdgeFunctionMusicProvider.withInvoker((name, {body}) async {
        throw Exception('socket closed');
      });

      expect(
        () => provider.generate(const AIGenerationRequest(prompt: 'a song')),
        throwsA(isA<GenerationException>()),
      );
    });

    test('throws when the response reports success but has no audio', () {
      final provider = EdgeFunctionMusicProvider.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {'success': true},
        );
      });

      expect(
        () => provider.generate(const AIGenerationRequest(prompt: 'a song')),
        throwsA(isA<GenerationException>()),
      );
    });
  });
}
