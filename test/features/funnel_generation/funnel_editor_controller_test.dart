import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_model.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_schema.dart';
import 'package:createai_studio/features/funnel_generation/data/models/public_funnel_view.dart';
import 'package:createai_studio/features/funnel_generation/data/repositories/funnel_repository.dart';
import 'package:createai_studio/features/funnel_generation/presentation/providers/funnel_providers.dart';

FunnelSchema _schema({List<FunnelSection>? sections}) => FunnelSchema(
      name: 'Test Funnel',
      type: 'custom',
      metadata: const FunnelMetadataInfo(),
      theme: const FunnelTheme(),
      sections: sections ??
          const [
            FunnelSection(id: 'hero-1', type: 'hero', content: {'headline': 'Hello'}),
            FunnelSection(id: 'faq-1', type: 'faq', content: {'title': 'FAQ'}),
          ],
      seo: const FunnelSeo(title: 'Test', description: 'Test', ogTitle: 'Test', ogDescription: 'Test'),
      settings: const FunnelSettings(),
    );

FunnelModel _model(FunnelSchema content) => FunnelModel(
      id: 'funnel-1',
      userId: 'user-1',
      generationId: 'gen-1',
      name: content.name,
      funnelType: content.type,
      status: 'draft',
      schemaVersion: 1,
      content: content,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

class FakeFunnelRepository implements FunnelRepository {
  FakeFunnelRepository(this._funnel);
  FunnelModel _funnel;
  FunnelModel? lastSaved;
  bool failSave = false;

  @override
  Future<Result<FunnelModel>> getFunnel(String id) async => Result.success(_funnel);

  @override
  Future<Result<FunnelModel?>> getFunnelByGenerationId(String generationId) async =>
      Result.success(_funnel);

  @override
  Future<Result<List<FunnelModel>>> getFunnels(String userId, {String? projectId}) async =>
      Result.success([_funnel]);

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
    final inserted = FunnelModel(
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
    return Result.success(inserted);
  }

  @override
  Future<Result<FunnelModel>> updateFunnel(
    String id, {
    String? name,
    FunnelSchema? content,
    String? status,
  }) async {
    if (failSave) {
      return const Result.failure(GenerationException(message: 'Save failed'));
    }
    _funnel = _funnel.copyWith(name: name, content: content, status: status);
    lastSaved = _funnel;
    return Result.success(_funnel);
  }

  @override
  Future<Result<FunnelModel>> publishFunnel(String id) => throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> unpublishFunnel(String id) => throw UnimplementedError();
  @override
  Future<Result<PublicFunnelView?>> getPublicFunnel(String slug) => throw UnimplementedError();
}

void main() {
  late FakeFunnelRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeFunnelRepository(_model(_schema()));
    container = ProviderContainer(overrides: [
      funnelRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
  });

  Future<FunnelEditorController> loaded() async {
    await container.read(funnelEditorProvider('funnel-1').future);
    return container.read(funnelEditorProvider('funnel-1').notifier);
  }

  test('loads the funnel via the repository', () async {
    await loaded();
    final state = container.read(funnelEditorProvider('funnel-1'));
    expect(state.value?.content.sections, hasLength(2));
  });

  test('updateSectionContent merges changes without dropping other keys', () async {
    final controller = await loaded();
    controller.updateSectionContent('hero-1', {'subheadline': 'New subheadline'});

    final section = container.read(funnelEditorProvider('funnel-1')).value!.content.sections.first;
    expect(section.content['headline'], 'Hello');
    expect(section.content['subheadline'], 'New subheadline');
  });

  test('setSectionVisible toggles a single section', () async {
    final controller = await loaded();
    controller.setSectionVisible('faq-1', false);

    final sections = container.read(funnelEditorProvider('funnel-1')).value!.content.sections;
    expect(sections.firstWhere((s) => s.id == 'faq-1').visible, isFalse);
    expect(sections.firstWhere((s) => s.id == 'hero-1').visible, isTrue);
  });

  test('removeSection removes only the targeted section', () async {
    final controller = await loaded();
    controller.removeSection('faq-1');

    final sections = container.read(funnelEditorProvider('funnel-1')).value!.content.sections;
    expect(sections, hasLength(1));
    expect(sections.single.id, 'hero-1');
  });

  test('addSection appends a new section with sensible default content', () async {
    final controller = await loaded();
    controller.addSection(FunnelSectionType.testimonials);

    final sections = container.read(funnelEditorProvider('funnel-1')).value!.content.sections;
    expect(sections, hasLength(3));
    expect(sections.last.type, 'testimonials');
    expect(sections.last.content['items'], isNotEmpty);
  });

  test('moveSectionUp/moveSectionDown reorder sections', () async {
    final controller = await loaded();
    controller.moveSectionDown('hero-1');

    var sections = container.read(funnelEditorProvider('funnel-1')).value!.content.sections;
    expect(sections.map((s) => s.id), ['faq-1', 'hero-1']);

    controller.moveSectionUp('hero-1');
    sections = container.read(funnelEditorProvider('funnel-1')).value!.content.sections;
    expect(sections.map((s) => s.id), ['hero-1', 'faq-1']);
  });

  test('moveSectionUp is a no-op at the top of the list', () async {
    final controller = await loaded();
    controller.moveSectionUp('hero-1');

    final sections = container.read(funnelEditorProvider('funnel-1')).value!.content.sections;
    expect(sections.map((s) => s.id), ['hero-1', 'faq-1']);
  });

  test('reorderSections supports drag-and-drop style reordering', () async {
    final controller = await loaded();
    controller.reorderSections(0, 2);

    final sections = container.read(funnelEditorProvider('funnel-1')).value!.content.sections;
    expect(sections.map((s) => s.id), ['faq-1', 'hero-1']);
  });

  test('save persists the current in-memory content via the repository', () async {
    final controller = await loaded();
    controller.updateName('Renamed Funnel');

    final ok = await controller.save();

    expect(ok, isTrue);
    expect(repository.lastSaved?.content.name, 'Renamed Funnel');
  });

  test('save returns false when the repository update fails', () async {
    repository.failSave = true;
    final controller = await loaded();

    final ok = await controller.save();

    expect(ok, isFalse);
  });
}
