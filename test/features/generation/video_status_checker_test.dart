import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:createai_studio/features/generation/services/video_status_checker.dart';

void main() {
  group('VideoStatusChecker', () {
    test('reports processing while the provider job is still running', () async {
      final checker = VideoStatusChecker.withInvoker((name, {body}) async {
        expect(name, 'video-status');
        expect((body as Map)['generationId'], 'gen-1');
        expect(body['jobId'], 'job-1');
        return const FunctionResponse(
          status: 200,
          data: {'success': true, 'status': 'processing'},
        );
      });

      final result = await checker.check(generationId: 'gen-1', jobId: 'job-1');

      expect(result.isProcessing, isTrue);
    });

    test('maps a completed response to video/thumbnail URLs and storage paths', () async {
      final checker = VideoStatusChecker.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'status': 'completed',
            'video': {
              'storagePath': 'user-1/generations/req-1/result.mp4',
              'signedUrl': 'https://example.com/result.mp4',
              'mimeType': 'video/mp4',
              'fileSize': 123456,
              'durationSeconds': 6,
            },
            'thumbnail': {
              'storagePath': 'user-1/generations/req-1/thumbnail.png',
              'signedUrl': 'https://example.com/thumbnail.png',
            },
            'metadata': {'aspectRatio': '16:9'},
          },
        );
      });

      final result = await checker.check(generationId: 'gen-1', jobId: 'job-1');

      expect(result.isCompleted, isTrue);
      expect(result.videoUrl, 'https://example.com/result.mp4');
      expect(result.videoStoragePath, 'user-1/generations/req-1/result.mp4');
      expect(result.thumbnailUrl, 'https://example.com/thumbnail.png');
      expect(result.thumbnailStoragePath, 'user-1/generations/req-1/thumbnail.png');
      expect(result.metadata['aspectRatio'], '16:9');
    });

    test('maps a completed response with no thumbnail', () async {
      final checker = VideoStatusChecker.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {
            'success': true,
            'status': 'completed',
            'video': {
              'storagePath': 'p',
              'signedUrl': 'https://example.com/result.mp4',
              'mimeType': 'video/mp4',
            },
            'thumbnail': null,
            'metadata': {},
          },
        );
      });

      final result = await checker.check(generationId: 'gen-1', jobId: 'job-1');

      expect(result.isCompleted, isTrue);
      expect(result.thumbnailUrl, isNull);
    });

    test('reports failed with the provider error message', () async {
      final checker = VideoStatusChecker.withInvoker((name, {body}) async {
        return const FunctionResponse(
          status: 200,
          data: {'success': true, 'status': 'failed', 'error': 'The provider job failed.'},
        );
      });

      final result = await checker.check(generationId: 'gen-1', jobId: 'job-1');

      expect(result.isFailed, isTrue);
      expect(result.error, 'The provider job failed.');
    });

    test('reports failed when the Edge Function returns an error response', () async {
      final checker = VideoStatusChecker.withInvoker((name, {body}) async {
        throw const FunctionException(
          status: 403,
          details: {'success': false, 'error': 'This job could not be verified.'},
        );
      });

      final result = await checker.check(generationId: 'gen-1', jobId: 'job-1');

      expect(result.isFailed, isTrue);
      expect(result.error, 'This job could not be verified.');
    });

    test('treats a transient network error as still processing, not failed', () async {
      final checker = VideoStatusChecker.withInvoker((name, {body}) async {
        throw Exception('socket closed');
      });

      final result = await checker.check(generationId: 'gen-1', jobId: 'job-1');

      expect(result.isProcessing, isTrue);
    });
  });
}
