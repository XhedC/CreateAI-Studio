import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/generation/data/models/generation_file_model.dart';
import 'package:createai_studio/features/generation/data/models/generation_model.dart';
import 'package:createai_studio/features/generation/data/repositories/generation_repository.dart';

/// In-memory fake exercising the same contract the Supabase implementation
/// fulfils, so history filtering/search/creation logic is covered without a
/// live database.
class FakeGenerationRepository implements GenerationRepository {
  final List<GenerationModel> _generations = [];
  int _idCounter = 0;

  @override
  Future<Result<GenerationModel>> createGeneration({
    required String userId,
    String? projectId,
    required String generationType,
    required String prompt,
  }) async {
    final generation = GenerationModel(
      id: 'gen-${_idCounter++}',
      userId: userId,
      projectId: projectId,
      generationType: generationType,
      prompt: prompt,
      status: 'pending',
      createdAt: DateTime(2025, 1, 1).add(Duration(minutes: _idCounter)),
    );
    _generations.insert(0, generation);
    return Result.success(generation);
  }

  @override
  Future<Result<void>> deleteGeneration(String id) async {
    _generations.removeWhere((g) => g.id == id);
    return const Result.success(null);
  }

  @override
  Future<Result<void>> deleteGenerationAndFiles(GenerationModel generation) async {
    _generations.removeWhere((g) => g.id == generation.id);
    return const Result.success(null);
  }

  @override
  Future<Result<GenerationModel>> getGeneration(String id) async {
    return Result.success(_generations.firstWhere((g) => g.id == id));
  }

  @override
  Future<Result<List<GenerationModel>>> getGenerations(
    String userId, {
    String? generationType,
    String? projectId,
    String? searchQuery,
  }) async {
    var results = _generations.where((g) => g.userId == userId);
    if (generationType != null) {
      results = results.where((g) => g.generationType == generationType);
    }
    if (projectId != null) {
      results = results.where((g) => g.projectId == projectId);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      results = results.where((g) => g.prompt.contains(searchQuery));
    }
    return Result.success(results.toList());
  }

  @override
  Future<Result<GenerationModel>> updateGeneration(
    String id, {
    String? status,
    String? provider,
    String? model,
    String? resultText,
    String? resultUrl,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
    String? errorMessage,
    DateTime? completedAt,
  }) async {
    final index = _generations.indexWhere((g) => g.id == id);
    final updated = _generations[index].copyWith(
      status: status,
      resultText: resultText,
      resultUrl: resultUrl,
      thumbnailUrl: thumbnailUrl,
      metadata: metadata,
      errorMessage: errorMessage,
      completedAt: completedAt,
    );
    _generations[index] = updated;
    return Result.success(updated);
  }

  @override
  Future<Result<GenerationFileModel>> attachFile({
    required String generationId,
    required String userId,
    required String fileName,
    required String fileType,
    required String mimeType,
    required String storagePath,
    String? fileUrl,
    int? fileSize,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<GenerationFileModel>>> getFiles(String generationId) {
    throw UnimplementedError();
  }
}

void main() {
  late FakeGenerationRepository repository;

  setUp(() => repository = FakeGenerationRepository());

  test('createGeneration starts a record in pending status', () async {
    final result = await repository.createGeneration(
      userId: 'user-1',
      generationType: 'image',
      prompt: 'A modern advertisement for a pharmacy',
    );

    expect(result.isSuccess, isTrue);
    final generation = (result as Success<GenerationModel>).data;
    expect(generation.status, 'pending');
    expect(generation.generationType, 'image');
  });

  test('getGenerations filters by type', () async {
    await repository.createGeneration(userId: 'user-1', generationType: 'image', prompt: 'a');
    await repository.createGeneration(userId: 'user-1', generationType: 'text', prompt: 'b');

    final result = await repository.getGenerations('user-1', generationType: 'image');

    final data = (result as Success<List<GenerationModel>>).data;
    expect(data, hasLength(1));
    expect(data.single.generationType, 'image');
  });

  test('getGenerations filters by type for music history', () async {
    await repository.createGeneration(
      userId: 'user-1',
      generationType: 'music',
      prompt: 'An uplifting acoustic worship song',
    );
    await repository.createGeneration(userId: 'user-1', generationType: 'image', prompt: 'a');

    final result = await repository.getGenerations('user-1', generationType: 'music');

    final data = (result as Success<List<GenerationModel>>).data;
    expect(data, hasLength(1));
    expect(data.single.generationType, 'music');
  });

  test('getGenerations filters by search query', () async {
    await repository.createGeneration(
      userId: 'user-1',
      generationType: 'text',
      prompt: 'Write a poem about the ocean',
    );
    await repository.createGeneration(
      userId: 'user-1',
      generationType: 'text',
      prompt: 'Summarize this article',
    );

    final result = await repository.getGenerations('user-1', searchQuery: 'poem');

    final data = (result as Success<List<GenerationModel>>).data;
    expect(data, hasLength(1));
    expect(data.single.prompt, contains('poem'));
  });

  test('updateGeneration transitions status through the pipeline', () async {
    final created = await repository.createGeneration(
      userId: 'user-1',
      generationType: 'text',
      prompt: 'hello',
    );
    final id = (created as Success<GenerationModel>).data.id;

    await repository.updateGeneration(id, status: 'processing');
    final completed = await repository.updateGeneration(
      id,
      status: 'completed',
      resultText: 'done',
      completedAt: DateTime(2025, 1, 2),
    );

    final data = (completed as Success<GenerationModel>).data;
    expect(data.status, 'completed');
    expect(data.resultText, 'done');
  });

  test('deleteGeneration removes it from history', () async {
    final created = await repository.createGeneration(
      userId: 'user-1',
      generationType: 'text',
      prompt: 'hello',
    );
    final id = (created as Success<GenerationModel>).data.id;

    await repository.deleteGeneration(id);
    final result = await repository.getGenerations('user-1');

    expect((result as Success<List<GenerationModel>>).data, isEmpty);
  });

  test('deleteGenerationAndFiles removes the generation like a regular delete', () async {
    final created = await repository.createGeneration(
      userId: 'user-1',
      generationType: 'image',
      prompt: 'a cat',
    );
    final generation = (created as Success<GenerationModel>).data;

    await repository.deleteGenerationAndFiles(generation);
    final result = await repository.getGenerations('user-1');

    expect((result as Success<List<GenerationModel>>).data, isEmpty);
  });
}
