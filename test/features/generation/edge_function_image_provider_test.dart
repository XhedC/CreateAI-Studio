import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/features/generation/services/ai_provider.dart';
import 'package:createai_studio/features/generation/services/edge_function_image_provider.dart';

void main() {
  group('EdgeFunctionImageProvider', () {
    test('maps a successful response to an AIGenerationResult', () async {
      final provider = EdgeFunctionImageProvider.withInvoker((name, {body}) async {
        expect(name, 'generate-image');
        expect((body as Map)['prompt'], 'a cat');
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'provider': 'mock',
            'model': 'mock-image-v1',
            'images': [
              {
                'storagePath': 'user-1/generations/req-1/result.png',
                'signedUrl': 'https://example.com/result.png',
                'mimeType': 'image/png',
                'fileSize': 1024,
              },
            ],
            'metadata': {'aspectRatio': '1:1'},
          },
        );
      });

      final result = await provider.generate(
        const AIGenerationRequest(prompt: 'a cat'),
      );

      expect(result.resultUrl, 'https://example.com/result.png');
      expect(result.thumbnailUrl, 'https://example.com/result.png');
      expect(result.metadata['provider'], 'mock');
      expect(result.metadata['model'], 'mock-image-v1');
      expect(result.metadata['storagePath'], 'user-1/generations/req-1/result.png');
      expect(result.additionalFiles, isEmpty);
    });

    test('maps additional images beyond the first into additionalFiles', () async {
      final provider = EdgeFunctionImageProvider.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'provider': 'openai',
            'model': 'gpt-image-1',
            'images': [
              {
                'storagePath': 'user-1/generations/req-1/result.png',
                'signedUrl': 'https://example.com/1.png',
                'mimeType': 'image/png',
                'fileSize': 100,
              },
              {
                'storagePath': 'user-1/generations/req-1/result-2.png',
                'signedUrl': 'https://example.com/2.png',
                'mimeType': 'image/png',
                'fileSize': 200,
              },
            ],
            'metadata': {},
          },
        );
      });

      final result = await provider.generate(
        const AIGenerationRequest(prompt: 'a cat', options: {'numberOfImages': 2}),
      );

      expect(result.additionalFiles, hasLength(1));
      expect(result.additionalFiles.single.storagePath,
          'user-1/generations/req-1/result-2.png');
      expect(result.additionalFiles.single.fileUrl, 'https://example.com/2.png');
    });

    test('sends the generationId from the request', () async {
      Map<dynamic, dynamic>? capturedBody;
      final provider = EdgeFunctionImageProvider.withInvoker((name, {body}) async {
        capturedBody = body as Map;
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'images': [
              {'storagePath': 'p', 'signedUrl': 'https://example.com/1.png', 'mimeType': 'image/png'},
            ],
            'metadata': {},
          },
        );
      });

      await provider.generate(
        const AIGenerationRequest(prompt: 'a cat', generationId: 'gen-123'),
      );

      expect(capturedBody!['generationId'], 'gen-123');
    });

    test('forwards the first attachment URL as referenceImagePath', () async {
      String? capturedReferencePath;
      final provider = EdgeFunctionImageProvider.withInvoker((name, {body}) async {
        capturedReferencePath = (body as Map)['referenceImagePath'] as String?;
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'provider': 'mock',
            'model': 'mock-image-v1',
            'images': [
              {
                'storagePath': 'p',
                'signedUrl': 'https://example.com/1.png',
                'mimeType': 'image/png',
              },
            ],
            'metadata': {},
          },
        );
      });

      await provider.generate(
        const AIGenerationRequest(
          prompt: 'a cat',
          attachmentUrls: ['user-1/uploads/ref.png'],
        ),
      );

      expect(capturedReferencePath, 'user-1/uploads/ref.png');
    });

    test('throws a GenerationException with the server message on FunctionException', () {
      final provider = EdgeFunctionImageProvider.withInvoker((name, {body}) async {
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
        () => provider.generate(const AIGenerationRequest(prompt: 'a cat')),
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
      final provider = EdgeFunctionImageProvider.withInvoker((name, {body}) async {
        throw Exception('socket closed');
      });

      expect(
        () => provider.generate(const AIGenerationRequest(prompt: 'a cat')),
        throwsA(isA<GenerationException>()),
      );
    });

    test('throws when the response reports success but has no images', () {
      final provider = EdgeFunctionImageProvider.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {'success': true, 'images': <Map<String, dynamic>>[]},
        );
      });

      expect(
        () => provider.generate(const AIGenerationRequest(prompt: 'a cat')),
        throwsA(isA<GenerationException>()),
      );
    });
  });
}
