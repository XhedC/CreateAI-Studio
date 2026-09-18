import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_model.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_schema.dart';
import 'package:createai_studio/features/funnel_generation/data/repositories/funnel_repository.dart';
import 'package:createai_studio/features/funnel_generation/presentation/providers/funnel_providers.dart';
import 'package:createai_studio/features/funnel_generation/presentation/screens/funnel_editor_screen.dart';

FunnelSchema _schema() => const FunnelSchema(
      name: 'Test Funnel',
      type: 'custom',
      metadata: FunnelMetadataInfo(),
      theme: FunnelTheme(),
      sections: [
        FunnelSection(id: 'hero-1', type: 'hero', content: {'headline': 'Hello there'}),
        FunnelSection(id: 'faq-1', type: 'faq', content: {'title': 'Frequently Asked Questions'}),
      ],
      seo: FunnelSeo(title: 'Test', description: 'Test', ogTitle: 'Test', ogDescription: 'Test'),
      settings: FunnelSettings(),
    );

class _FakeFunnelRepository implements FunnelRepository {
  _FakeFunnelRepository(this._funnel);
  FunnelModel _funnel;
  FunnelModel? lastSaved;

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
  }) =>
      throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> updateFunnel(
    String id, {
    String? name,
    FunnelSchema? content,
    String? status,
  }) async {
    _funnel = _funnel.copyWith(name: name, content: content, status: status);
    lastSaved = _funnel;
    return Result.success(_funnel);
  }
}

FunnelModel _model() => FunnelModel(
      id: 'funnel-1',
      userId: 'user-1',
      generationId: 'gen-1',
      name: 'Test Funnel',
      funnelType: 'custom',
      status: 'draft',
      schemaVersion: 1,
      content: _schema(),
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

Future<_FakeFunnelRepository> _pumpScreen(WidgetTester tester) async {
  final repo = _FakeFunnelRepository(_model());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [funnelRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: FunnelEditorScreen(funnelId: 'funnel-1')),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('renders the funnel name and its sections', (tester) async {
    await _pumpScreen(tester);

    expect(find.widgetWithText(TextFormField, 'Test Funnel'), findsOneWidget);
    expect(find.text('Hero'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);
  });

  testWidgets('toggling the visibility switch updates section state', (tester) async {
    await _pumpScreen(tester);

    final switches = find.byType(Switch);
    expect(tester.widget<Switch>(switches.first).value, isTrue);

    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switches.first).value, isFalse);
  });

  testWidgets('deleting a section removes it after confirmation', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Hero'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Hero'), findsNothing);
    expect(find.text('FAQ'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('adding a section from the picker appends it to the list', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('Add Section'));
    await tester.pumpAndSettle();
    // The section-type picker sheet has its own (long) internal Scrollable,
    // distinct from the screen's - scroll within it to reach "Testimonials".
    await tester.scrollUntilVisible(
      find.text('Testimonials'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Testimonials'));
    await tester.pumpAndSettle();

    expect(find.text('Testimonials'), findsOneWidget);
  });

  testWidgets('Save persists the current content via the repository', (tester) async {
    final repo = await _pumpScreen(tester);

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(repo.lastSaved, isNotNull);
    expect(find.text('Funnel saved.'), findsOneWidget);
  });
}
