import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/generation/data/models/generation_model.dart';
import 'package:createai_studio/features/generation/data/repositories/generation_repository.dart';
import 'package:createai_studio/features/generation/presentation/providers/generation_providers.dart';
import 'package:createai_studio/features/generation/presentation/providers/video_polling_provider.dart';
import 'package:createai_studio/features/generation/services/video_status_checker.dart';

class MockGenerationRepository extends Mock implements GenerationRepository {}

GenerationModel _generation({String status = 'processing'}) => GenerationModel(
      id: 'gen-1',
      userId: 'user-1',
      generationType: 'video',
      prompt: 'a cinematic pharmacy ad',
      status: status,
      createdAt: DateTime(2025, 1, 1),
    );

/// Waits long enough for the polling controller's fire-and-forget `_poll`
/// future (and the fake invoker inside it) to finish at least one full
/// round trip, without needing to fake real [Timer]s.
Future<void> _flush() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  late MockGenerationRepository repository;

  setUp(() {
    repository = MockGenerationRepository();
    when(() => repository.updateGeneration(
          any(),
          status: any(named: 'status'),
          provider: any(named: 'provider'),
          model: any(named: 'model'),
          resultText: any(named: 'resultText'),
          resultUrl: any(named: 'resultUrl'),
          thumbnailUrl: any(named: 'thumbnailUrl'),
          metadata: any(named: 'metadata'),
          errorMessage: any(named: 'errorMessage'),
          completedAt: any(named: 'completedAt'),
        )).thenAnswer((_) async => Result.success(_generation(status: 'completed')));
  });

  ProviderContainer makeContainer(VideoStatusChecker checker) {
    final container = ProviderContainer(overrides: [
      generationRepositoryProvider.overrideWithValue(repository),
      videoStatusCheckerProvider.overrideWithValue(checker),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('a completed poll marks the generation completed with video/thumbnail metadata', () async {
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
          },
          'thumbnail': {
            'storagePath': 'user-1/generations/req-1/thumbnail.png',
            'signedUrl': 'https://example.com/thumbnail.png',
          },
          'metadata': {},
        },
      );
    });
    final container = makeContainer(checker);

    container.read(videoPollingProvider('gen-1').notifier).start('job-1');
    await _flush();

    verify(() => repository.updateGeneration(
          'gen-1',
          status: 'completed',
          resultUrl: 'https://example.com/result.mp4',
          thumbnailUrl: 'https://example.com/thumbnail.png',
          metadata: {
            'storagePath': 'user-1/generations/req-1/result.mp4',
            'thumbnailStoragePath': 'user-1/generations/req-1/thumbnail.png',
          },
          completedAt: any(named: 'completedAt'),
        )).called(1);
    expect(container.read(videoPollingProvider('gen-1')), isFalse);
  });

  test('a failed poll marks the generation failed with the provider error', () async {
    final checker = VideoStatusChecker.withInvoker((name, {body}) async {
      return const FunctionResponse(
        status: 200,
        data: {'success': true, 'status': 'failed', 'error': 'The provider job failed.'},
      );
    });
    final container = makeContainer(checker);

    container.read(videoPollingProvider('gen-1').notifier).start('job-1');
    await _flush();

    verify(() => repository.updateGeneration(
          'gen-1',
          status: 'failed',
          errorMessage: 'The provider job failed.',
          completedAt: any(named: 'completedAt'),
        )).called(1);
  });

  test('start() is a no-op while a poll is already in flight for the same generation', () async {
    final completer = Completer<FunctionResponse>();
    var invokeCount = 0;
    final checker = VideoStatusChecker.withInvoker((name, {body}) async {
      invokeCount++;
      return completer.future;
    });
    final container = makeContainer(checker);
    final controller = container.read(videoPollingProvider('gen-1').notifier);

    controller.start('job-1');
    controller.start('job-1'); // should be ignored - already polling
    expect(container.read(videoPollingProvider('gen-1')), isTrue);

    completer.complete(
      const FunctionResponse(
        status: 200,
        data: {'success': true, 'status': 'processing'},
      ),
    );
    await _flush();

    expect(invokeCount, 1);
  });

  test('cancel() stops polling and marks the generation cancelled', () async {
    final checker = VideoStatusChecker.withInvoker((name, {body}) async {
      // A slow/never-resolving check - cancel() must not depend on it.
      return Completer<FunctionResponse>().future;
    });
    final container = makeContainer(checker);
    final controller = container.read(videoPollingProvider('gen-1').notifier);

    controller.start('job-1');
    await controller.cancel();

    expect(container.read(videoPollingProvider('gen-1')), isFalse);
    verify(() => repository.updateGeneration(
          'gen-1',
          status: 'cancelled',
          completedAt: any(named: 'completedAt'),
        )).called(1);
  });
}
