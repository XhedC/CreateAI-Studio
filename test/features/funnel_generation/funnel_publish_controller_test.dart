import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_model.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_schema.dart';
import 'package:createai_studio/features/funnel_generation/data/models/public_funnel_view.dart';
import 'package:createai_studio/features/funnel_generation/data/repositories/funnel_repository.dart';
import 'package:createai_studio/features/funnel_generation/presentation/providers/funnel_providers.dart';

FunnelModel _funnel({bool published = false, String? publicSlug}) => FunnelModel(
      id: 'funnel-1',
      userId: 'user-1',
      generationId: 'gen-1',
      name: 'Test Funnel',
      funnelType: 'custom',
      status: 'draft',
      schemaVersion: 1,
      content: const FunnelSchema(
        name: 'Test Funnel',
        type: 'custom',
        metadata: FunnelMetadataInfo(),
        theme: FunnelTheme(),
        sections: [FunnelSection(id: 'hero-1', type: 'hero', content: {'headline': 'Hi'})],
        seo: FunnelSeo(title: 'Test', description: 'Test', ogTitle: 'Test', ogDescription: 'Test'),
        settings: FunnelSettings(),
      ),
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      published: published,
      publicSlug: publicSlug,
    );

class _FakeFunnelRepository implements FunnelRepository {
  bool failPublish = false;
  bool failUnpublish = false;
  String? publishErrorMessage;
  FunnelModel current = _funnel();

  @override
  Future<Result<FunnelModel>> publishFunnel(String id) async {
    if (failPublish) {
      return Result.failure(PublishException(
        message: publishErrorMessage ?? 'Unable to publish.',
        code: 'VALIDATION_FAILED',
      ));
    }
    current = current.copyWith(
      published: true,
      publicSlug: current.publicSlug ?? 'test-funnel',
      publishedAt: DateTime(2025, 1, 2),
      publishedVersion: current.publishedVersion + 1,
    );
    return Result.success(current);
  }

  @override
  Future<Result<FunnelModel>> unpublishFunnel(String id) async {
    if (failUnpublish) {
      return const Result.failure(PublishException(message: 'Unable to unpublish.'));
    }
    current = current.copyWith(published: false, unpublishedAt: DateTime(2025, 1, 3));
    return Result.success(current);
  }

  @override
  Future<Result<PublicFunnelView?>> getPublicFunnel(String slug) => throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> getFunnel(String id) => throw UnimplementedError();
  @override
  Future<Result<FunnelModel?>> getFunnelByGenerationId(String generationId) =>
      throw UnimplementedError();
  @override
  Future<Result<List<FunnelModel>>> getFunnels(String userId, {String? projectId}) =>
      throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> insertFunnel({
    required String userId,
    String? projectId,
    required String generationId,
    required String name,
    String? description,
    required String funnelType,
    required FunnelSchema content,
  }) =>
      throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> updateFunnel(String id, {String? name, FunnelSchema? content, String? status}) =>
      throw UnimplementedError();
}

void main() {
  late _FakeFunnelRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeFunnelRepository();
    container = ProviderContainer(overrides: [
      funnelRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  });

  test('publish() succeeds and assigns a slug on first publish', () async {
    final controller = container.read(funnelPublishControllerProvider.notifier);

    final ok = await controller.publish('funnel-1');

    expect(ok, isTrue);
    final result = container.read(funnelPublishControllerProvider).value;
    expect(result?.published, isTrue);
    expect(result?.publicSlug, 'test-funnel');
    expect(result?.publishedVersion, 1);
  });

  test('publish() on an already-published funnel reuses the slug and increments the version', () async {
    repo.current = _funnel(published: true, publicSlug: 'test-funnel');
    final controller = container.read(funnelPublishControllerProvider.notifier);

    await controller.publish('funnel-1');

    expect(repo.current.publicSlug, 'test-funnel');
    expect(repo.current.publishedVersion, 1);
  });

  test('publish() surfaces the validation error message on failure', () async {
    repo.failPublish = true;
    repo.publishErrorMessage = 'Your funnel needs a name before it can be published.';
    final controller = container.read(funnelPublishControllerProvider.notifier);

    final ok = await controller.publish('funnel-1');

    expect(ok, isFalse);
    final error = container.read(funnelPublishControllerProvider).error;
    expect(error, isA<PublishException>());
    expect((error as PublishException).message, 'Your funnel needs a name before it can be published.');
  });

  test('unpublish() clears the published flag but the repository keeps the slug', () async {
    repo.current = _funnel(published: true, publicSlug: 'test-funnel');
    final controller = container.read(funnelPublishControllerProvider.notifier);

    final ok = await controller.unpublish('funnel-1');

    expect(ok, isTrue);
    expect(repo.current.published, isFalse);
    expect(repo.current.publicSlug, 'test-funnel'); // stable across unpublish
  });

  test('unpublish() failure leaves an AsyncError with a friendly message', () async {
    repo.failUnpublish = true;
    final controller = container.read(funnelPublishControllerProvider.notifier);

    final ok = await controller.unpublish('funnel-1');

    expect(ok, isFalse);
    expect(container.read(funnelPublishControllerProvider).hasError, isTrue);
  });
}
