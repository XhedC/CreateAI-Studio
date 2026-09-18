import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/auth/data/models/app_user.dart';
import 'package:createai_studio/features/auth/data/repositories/auth_repository.dart';
import 'package:createai_studio/features/auth/presentation/providers/auth_providers.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_model.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_schema.dart';
import 'package:createai_studio/features/funnel_generation/data/models/public_funnel_view.dart';
import 'package:createai_studio/features/funnel_generation/data/repositories/funnel_repository.dart';
import 'package:createai_studio/features/funnel_generation/presentation/providers/funnel_providers.dart';
import 'package:createai_studio/features/generation/data/models/generation_file_model.dart';
import 'package:createai_studio/features/generation/data/models/generation_model.dart';
import 'package:createai_studio/features/generation/data/repositories/generation_repository.dart';
import 'package:createai_studio/features/generation/presentation/providers/generation_providers.dart';

class _FakeAuthRepository implements AuthRepository {
  final _user = const AppUser(id: 'user-1', email: 'user@example.com');
  @override
  AppUser? get currentUser => _user;
  @override
  Stream<AppUser?> get authStateChanges => Stream.value(_user);
  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) async =>
      Result.success(_user);
  @override
  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async =>
      Result.success(_user);
  @override
  Future<Result<void>> signOut() async => const Result.success(null);
  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async => const Result.success(null);
}

class _FakeGenerationRepository implements GenerationRepository {
  bool failCreate = false;
  final List<Map<String, dynamic>> updates = [];

  @override
  Future<Result<GenerationModel>> createGeneration({
    required String userId,
    String? projectId,
    required String generationType,
    required String prompt,
  }) async {
    if (failCreate) {
      return const Result.failure(NetworkException());
    }
    return Result.success(GenerationModel(
      id: 'gen-2',
      userId: userId,
      projectId: projectId,
      generationType: generationType,
      prompt: prompt,
      status: 'pending',
      createdAt: DateTime(2025, 1, 2),
    ));
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
    updates.add({'id': id, 'status': status, 'metadata': metadata});
    return Result.success(GenerationModel(
      id: id,
      userId: 'user-1',
      generationType: 'funnel',
      prompt: 'Copy of Test Funnel',
      status: status ?? 'completed',
      createdAt: DateTime(2025, 1, 2),
    ));
  }

  @override
  Future<Result<void>> deleteGeneration(String id) async => const Result.success(null);
  @override
  Future<Result<void>> deleteGenerationAndFiles(GenerationModel generation) async =>
      const Result.success(null);
  @override
  Future<Result<GenerationModel>> getGeneration(String id) => throw UnimplementedError();
  @override
  Future<Result<List<GenerationModel>>> getGenerations(
    String userId, {
    String? generationType,
    String? projectId,
    String? searchQuery,
  }) async =>
      const Result.success([]);
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
  }) =>
      throw UnimplementedError();
  @override
  Future<Result<List<GenerationFileModel>>> getFiles(String generationId) =>
      throw UnimplementedError();
}

class _FakeFunnelRepository implements FunnelRepository {
  bool failInsert = false;
  FunnelModel? inserted;

  @override
  Future<Result<FunnelModel>> insertFunnel({
    required String userId,
    String? projectId,
    required String generationId,
    required String name,
    String? description,
    required String funnelType,
    required FunnelSchema content,
  }) async {
    if (failInsert) {
      return const Result.failure(NetworkException());
    }
    inserted = FunnelModel(
      id: 'funnel-2',
      userId: userId,
      projectId: projectId,
      generationId: generationId,
      name: name,
      description: description,
      funnelType: funnelType,
      status: 'draft',
      schemaVersion: content.version,
      content: content,
      createdAt: DateTime(2025, 1, 2),
      updatedAt: DateTime(2025, 1, 2),
    );
    return Result.success(inserted!);
  }

  @override
  Future<Result<FunnelModel>> getFunnel(String id) => throw UnimplementedError();
  @override
  Future<Result<FunnelModel?>> getFunnelByGenerationId(String generationId) =>
      throw UnimplementedError();
  @override
  Future<Result<List<FunnelModel>>> getFunnels(String userId, {String? projectId}) =>
      throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> updateFunnel(String id, {String? name, FunnelSchema? content, String? status}) =>
      throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> publishFunnel(String id) => throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> unpublishFunnel(String id) => throw UnimplementedError();
  @override
  Future<Result<PublicFunnelView?>> getPublicFunnel(String slug) => throw UnimplementedError();
}

FunnelModel _original() => FunnelModel(
      id: 'funnel-1',
      userId: 'user-1',
      generationId: 'gen-1',
      name: 'Test Funnel',
      funnelType: 'custom',
      status: 'draft',
      schemaVersion: 1,
      content: FunnelSchema(
        name: 'Test Funnel',
        type: 'custom',
        metadata: const FunnelMetadataInfo(),
        theme: const FunnelTheme(),
        sections: const [FunnelSection(id: 'hero-1', type: 'hero', content: {'headline': 'Hi'})],
        seo: const FunnelSeo(title: 'Test', description: 'Test', ogTitle: 'Test', ogDescription: 'Test'),
        settings: const FunnelSettings(),
      ),
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

void main() {
  late _FakeGenerationRepository genRepo;
  late _FakeFunnelRepository funnelRepo;
  late ProviderContainer container;

  setUp(() {
    genRepo = _FakeGenerationRepository();
    funnelRepo = _FakeFunnelRepository();
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      generationRepositoryProvider.overrideWithValue(genRepo),
      funnelRepositoryProvider.overrideWithValue(funnelRepo),
    ]);
    addTearDown(container.dispose);
    // authStateProvider is a StreamProvider - a bare container.read() does
    // not keep its subscription alive in Riverpod 3 (it needs an active
    // listener, exactly like the real app's ambient router/Home screen
    // watchers), so without this, .value stays null forever and
    // duplicate() would always see "no signed-in user". See
    // lead_form_widget_test.dart for the same fix with more detail.
    container.listen(authStateProvider, (previous, next) {});
  });

  test('duplicate() creates a new generation and a new funnel, leaving the original untouched', () async {
    final controller = container.read(funnelDuplicateControllerProvider.notifier);

    final ok = await controller.duplicate(_original());

    expect(ok, isTrue);
    expect(funnelRepo.inserted?.name, 'Copy of Test Funnel');
    expect(funnelRepo.inserted?.generationId, 'gen-2');
    expect(funnelRepo.inserted?.content.name, 'Copy of Test Funnel');
    // The original's own id/content are never mutated by duplicate().
    expect(_original().name, 'Test Funnel');
  });

  test('duplicate() returns false when creating the generation fails', () async {
    genRepo.failCreate = true;
    final controller = container.read(funnelDuplicateControllerProvider.notifier);

    final ok = await controller.duplicate(_original());

    expect(ok, isFalse);
    expect(funnelRepo.inserted, isNull);
  });

  test('duplicate() returns false when inserting the funnel fails', () async {
    funnelRepo.failInsert = true;
    final controller = container.read(funnelDuplicateControllerProvider.notifier);

    final ok = await controller.duplicate(_original());

    expect(ok, isFalse);
  });
}
