import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:createai_studio/core/constants/creation_type.dart';
import 'package:createai_studio/core/network/network_service.dart';
import 'package:createai_studio/features/generation/data/models/generation_file_model.dart';
import 'package:createai_studio/features/generation/data/models/generation_model.dart';
import 'package:createai_studio/features/generation/data/repositories/generation_repository.dart';
import 'package:createai_studio/features/generation/services/ai_provider.dart';
import 'package:createai_studio/features/generation/services/generation_orchestrator.dart';
import 'package:createai_studio/core/utils/result.dart';

class MockGenerationRepository extends Mock implements GenerationRepository {}

class MockNetworkService extends Mock implements NetworkService {}

class MockTextAIProvider extends Mock implements TextAIProvider {}

class MockMusicAIProvider extends Mock implements MusicAIProvider {}

GenerationModel _generation({String status = 'pending'}) => GenerationModel(
      id: 'gen-1',
      userId: 'user-1',
      generationType: 'text',
      prompt: 'hello world',
      status: status,
      createdAt: DateTime(2025, 1, 1),
    );

void main() {
  late MockGenerationRepository repository;
  late MockNetworkService network;
  late MockTextAIProvider provider;
  late GenerationOrchestrator orchestrator;

  setUpAll(() {
    registerFallbackValue(const AIGenerationRequest(prompt: 'fallback'));
  });

  setUp(() {
    repository = MockGenerationRepository();
    network = MockNetworkService();
    provider = MockTextAIProvider();

    when(() => provider.type).thenReturn(CreationType.text);
    when(() => provider.providerName).thenReturn('mock');
    when(() => provider.modelName).thenReturn('mock-text-v1');

    orchestrator = GenerationOrchestrator(
      repository: repository,
      networkService: network,
      providersByType: {CreationType.text: provider},
    );
  });

  test('rejects an empty prompt without touching the network or repository', () async {
    final result = await orchestrator.generate(
      userId: 'user-1',
      type: CreationType.text,
      prompt: '   ',
    );

    expect(result.isFailure, isTrue);
    verifyNever(() => network.isConnected);
    verifyNever(() => repository.createGeneration(
          userId: any(named: 'userId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        ));
  });

  test('fails fast when offline', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await orchestrator.generate(
      userId: 'user-1',
      type: CreationType.text,
      prompt: 'hello world',
    );

    expect(result.isFailure, isTrue);
    verifyNever(() => repository.createGeneration(
          userId: any(named: 'userId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        ));
  });

  test('runs the full pending -> processing -> completed pipeline', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => repository.createGeneration(
          userId: any(named: 'userId'),
          projectId: any(named: 'projectId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) async => Result.success(_generation()));
    when(() => repository.updateGeneration(any(),
        status: any(named: 'status'),
        provider: any(named: 'provider'),
        model: any(named: 'model'),
        resultText: any(named: 'resultText'),
        resultUrl: any(named: 'resultUrl'),
        thumbnailUrl: any(named: 'thumbnailUrl'),
        metadata: any(named: 'metadata'),
        errorMessage: any(named: 'errorMessage'),
        completedAt: any(named: 'completedAt'))).thenAnswer(
      (invocation) async => Result.success(
        _generation(status: invocation.namedArguments[#status] as String? ?? 'pending'),
      ),
    );
    when(() => provider.generate(any())).thenAnswer(
      (_) async => const AIGenerationResult(resultText: 'mock output'),
    );

    final result = await orchestrator.generate(
      userId: 'user-1',
      type: CreationType.text,
      prompt: 'hello world',
    );

    expect(result.isSuccess, isTrue);
    verify(() => repository.updateGeneration(any(), status: 'processing')).called(1);
    verify(() => repository.updateGeneration(
          any(),
          status: 'completed',
          provider: 'mock',
          model: 'mock-text-v1',
          resultText: any(named: 'resultText'),
          resultUrl: any(named: 'resultUrl'),
          thumbnailUrl: any(named: 'thumbnailUrl'),
          metadata: any(named: 'metadata'),
          completedAt: any(named: 'completedAt'),
        )).called(1);
  });

  test('marks the generation failed when the provider throws', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => repository.createGeneration(
          userId: any(named: 'userId'),
          projectId: any(named: 'projectId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) async => Result.success(_generation()));
    when(() => repository.updateGeneration(any(),
        status: any(named: 'status'),
        provider: any(named: 'provider'),
        model: any(named: 'model'),
        resultText: any(named: 'resultText'),
        resultUrl: any(named: 'resultUrl'),
        thumbnailUrl: any(named: 'thumbnailUrl'),
        metadata: any(named: 'metadata'),
        errorMessage: any(named: 'errorMessage'),
        completedAt: any(named: 'completedAt'))).thenAnswer(
      (_) async => Result.success(_generation(status: 'failed')),
    );
    when(() => provider.generate(any())).thenThrow(Exception('boom'));

    final result = await orchestrator.generate(
      userId: 'user-1',
      type: CreationType.text,
      prompt: 'hello world',
    );

    expect(result.isFailure, isTrue);
    verify(() => repository.updateGeneration(
          any(),
          status: 'failed',
          errorMessage: any(named: 'errorMessage'),
          completedAt: any(named: 'completedAt'),
        )).called(1);
  });

  test('persists additionalFiles via attachFile after a multi-image result', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => repository.createGeneration(
          userId: any(named: 'userId'),
          projectId: any(named: 'projectId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) async => Result.success(_generation()));
    when(() => repository.updateGeneration(any(),
        status: any(named: 'status'),
        provider: any(named: 'provider'),
        model: any(named: 'model'),
        resultText: any(named: 'resultText'),
        resultUrl: any(named: 'resultUrl'),
        thumbnailUrl: any(named: 'thumbnailUrl'),
        metadata: any(named: 'metadata'),
        errorMessage: any(named: 'errorMessage'),
        completedAt: any(named: 'completedAt'))).thenAnswer(
      (_) async => Result.success(_generation(status: 'completed')),
    );
    when(() => repository.attachFile(
          generationId: any(named: 'generationId'),
          userId: any(named: 'userId'),
          fileName: any(named: 'fileName'),
          fileType: any(named: 'fileType'),
          mimeType: any(named: 'mimeType'),
          storagePath: any(named: 'storagePath'),
          fileUrl: any(named: 'fileUrl'),
          fileSize: any(named: 'fileSize'),
        )).thenAnswer((_) async => Result.success(
          GenerationFileModel(
            id: 'file-1',
            generationId: 'gen-1',
            userId: 'user-1',
            fileName: 'image-2.png',
            fileType: 'text',
            mimeType: 'image/png',
            storagePath: 'user-1/generations/gen-1/image-2.png',
            createdAt: DateTime(2025, 1, 1),
          ),
        ));
    when(() => provider.generate(any())).thenAnswer(
      (_) async => const AIGenerationResult(
        resultUrl: 'https://example.com/1.png',
        additionalFiles: [
          GenerationResultFile(
            fileName: 'image-2.png',
            mimeType: 'image/png',
            storagePath: 'user-1/generations/gen-1/image-2.png',
          ),
        ],
      ),
    );

    final result = await orchestrator.generate(
      userId: 'user-1',
      type: CreationType.text,
      prompt: 'hello world',
    );

    expect(result.isSuccess, isTrue);
    verify(() => repository.attachFile(
          generationId: 'gen-1',
          userId: 'user-1',
          fileName: 'image-2.png',
          fileType: 'text',
          mimeType: 'image/png',
          storagePath: 'user-1/generations/gen-1/image-2.png',
          fileUrl: any(named: 'fileUrl'),
          fileSize: any(named: 'fileSize'),
        )).called(1);
  });

  test('prefers provider/model reported in result metadata over the static provider identity', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => repository.createGeneration(
          userId: any(named: 'userId'),
          projectId: any(named: 'projectId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) async => Result.success(_generation()));
    when(() => repository.updateGeneration(any(),
        status: any(named: 'status'),
        provider: any(named: 'provider'),
        model: any(named: 'model'),
        resultText: any(named: 'resultText'),
        resultUrl: any(named: 'resultUrl'),
        thumbnailUrl: any(named: 'thumbnailUrl'),
        metadata: any(named: 'metadata'),
        errorMessage: any(named: 'errorMessage'),
        completedAt: any(named: 'completedAt'))).thenAnswer(
      (_) async => Result.success(_generation(status: 'completed')),
    );
    when(() => provider.generate(any())).thenAnswer(
      (_) async => const AIGenerationResult(
        resultUrl: 'https://example.com/1.png',
        metadata: {'provider': 'openai', 'model': 'gpt-image-1'},
      ),
    );

    await orchestrator.generate(
      userId: 'user-1',
      type: CreationType.text,
      prompt: 'hello world',
    );

    verify(() => repository.updateGeneration(
          any(),
          status: 'completed',
          provider: 'openai',
          model: 'gpt-image-1',
          resultText: any(named: 'resultText'),
          resultUrl: any(named: 'resultUrl'),
          thumbnailUrl: any(named: 'thumbnailUrl'),
          metadata: any(named: 'metadata'),
          completedAt: any(named: 'completedAt'),
        )).called(1);
  });

  test('runs the full pipeline for a music generation (Phase 3)', () async {
    final musicProvider = MockMusicAIProvider();
    when(() => musicProvider.type).thenReturn(CreationType.music);
    when(() => musicProvider.providerName).thenReturn('mock');
    when(() => musicProvider.modelName).thenReturn('mock-music-v1');
    when(() => musicProvider.generate(any())).thenAnswer(
      (_) async => const AIGenerationResult(
        resultUrl: 'https://example.com/song.wav',
        metadata: {'genre': 'acoustic', 'mood': 'inspirational'},
      ),
    );

    final musicOrchestrator = GenerationOrchestrator(
      repository: repository,
      networkService: network,
      providersByType: {CreationType.music: musicProvider},
    );

    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => repository.createGeneration(
          userId: any(named: 'userId'),
          projectId: any(named: 'projectId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) async => Result.success(
          GenerationModel(
            id: 'gen-music-1',
            userId: 'user-1',
            generationType: 'music',
            prompt: 'an uplifting acoustic worship song',
            status: 'pending',
            createdAt: DateTime(2025, 1, 1),
          ),
        ));
    when(() => repository.updateGeneration(any(),
        status: any(named: 'status'),
        provider: any(named: 'provider'),
        model: any(named: 'model'),
        resultText: any(named: 'resultText'),
        resultUrl: any(named: 'resultUrl'),
        thumbnailUrl: any(named: 'thumbnailUrl'),
        metadata: any(named: 'metadata'),
        errorMessage: any(named: 'errorMessage'),
        completedAt: any(named: 'completedAt'))).thenAnswer(
      (_) async => Result.success(
        GenerationModel(
          id: 'gen-music-1',
          userId: 'user-1',
          generationType: 'music',
          prompt: 'an uplifting acoustic worship song',
          status: 'completed',
          resultUrl: 'https://example.com/song.wav',
          createdAt: DateTime(2025, 1, 1),
        ),
      ),
    );

    final result = await musicOrchestrator.generate(
      userId: 'user-1',
      type: CreationType.music,
      prompt: 'an uplifting acoustic worship song',
      options: const {'genre': 'acoustic', 'mood': 'inspirational'},
    );

    expect(result.isSuccess, isTrue);
    verify(() => repository.updateGeneration(
          any(),
          status: 'completed',
          provider: 'mock',
          model: 'mock-music-v1',
          resultText: any(named: 'resultText'),
          resultUrl: 'https://example.com/song.wav',
          thumbnailUrl: any(named: 'thumbnailUrl'),
          metadata: any(named: 'metadata'),
          completedAt: any(named: 'completedAt'),
        )).called(1);
  });

  test('marks a music generation failed when the provider throws', () async {
    final musicProvider = MockMusicAIProvider();
    when(() => musicProvider.type).thenReturn(CreationType.music);
    when(() => musicProvider.providerName).thenReturn('mock');
    when(() => musicProvider.modelName).thenReturn('mock-music-v1');
    when(() => musicProvider.generate(any())).thenThrow(Exception('provider unavailable'));

    final musicOrchestrator = GenerationOrchestrator(
      repository: repository,
      networkService: network,
      providersByType: {CreationType.music: musicProvider},
    );

    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => repository.createGeneration(
          userId: any(named: 'userId'),
          projectId: any(named: 'projectId'),
          generationType: any(named: 'generationType'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) async => Result.success(
          GenerationModel(
            id: 'gen-music-2',
            userId: 'user-1',
            generationType: 'music',
            prompt: 'a song',
            status: 'pending',
            createdAt: DateTime(2025, 1, 1),
          ),
        ));
    when(() => repository.updateGeneration(any(),
        status: any(named: 'status'),
        provider: any(named: 'provider'),
        model: any(named: 'model'),
        resultText: any(named: 'resultText'),
        resultUrl: any(named: 'resultUrl'),
        thumbnailUrl: any(named: 'thumbnailUrl'),
        metadata: any(named: 'metadata'),
        errorMessage: any(named: 'errorMessage'),
        completedAt: any(named: 'completedAt'))).thenAnswer(
      (_) async => Result.success(
        GenerationModel(
          id: 'gen-music-2',
          userId: 'user-1',
          generationType: 'music',
          prompt: 'a song',
          status: 'failed',
          createdAt: DateTime(2025, 1, 1),
        ),
      ),
    );

    final result = await musicOrchestrator.generate(
      userId: 'user-1',
      type: CreationType.music,
      prompt: 'a song',
    );

    expect(result.isFailure, isTrue);
    verify(() => repository.updateGeneration(
          any(),
          status: 'failed',
          errorMessage: any(named: 'errorMessage'),
          completedAt: any(named: 'completedAt'),
        )).called(1);
  });
}
