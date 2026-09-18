import 'package:flutter/material.dart';
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
import 'package:createai_studio/features/funnel_generation/presentation/screens/public_funnel_view_screen.dart';

/// A signed-out auth repository - a real anonymous visitor never has a
/// session, and the public funnel view must work exactly the same either
/// way (see app_router.dart's redirect exception for this route).
class _SignedOutAuthRepository implements AuthRepository {
  @override
  AppUser? get currentUser => null;
  @override
  Stream<AppUser?> get authStateChanges => Stream.value(null);
  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) =>
      throw UnimplementedError();
  @override
  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  }) =>
      throw UnimplementedError();
  @override
  Future<Result<void>> signOut() => throw UnimplementedError();
  @override
  Future<Result<void>> sendPasswordResetEmail(String email) => throw UnimplementedError();
}

class _FakeFunnelRepository implements FunnelRepository {
  PublicFunnelView? view;
  bool throwOnGet = false;

  @override
  Future<Result<PublicFunnelView?>> getPublicFunnel(String slug) async {
    if (throwOnGet) return const Result.failure(NetworkException());
    return Result.success(view);
  }

  @override
  Future<Result<FunnelModel>> publishFunnel(String id) => throw UnimplementedError();
  @override
  Future<Result<FunnelModel>> unpublishFunnel(String id) => throw UnimplementedError();
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

PublicFunnelView _view() => PublicFunnelView(
      name: 'Test Funnel',
      funnelType: 'custom',
      content: const FunnelSchema(
        name: 'Test Funnel',
        type: 'custom',
        metadata: FunnelMetadataInfo(),
        theme: FunnelTheme(),
        sections: [
          FunnelSection(
            id: 'hero-1',
            type: 'hero',
            content: {'headline': 'Welcome to the public page', 'cta': 'Get Started'},
          ),
        ],
        seo: FunnelSeo(title: 'Test', description: 'Test', ogTitle: 'Test', ogDescription: 'Test'),
        settings: FunnelSettings(),
      ),
      publicSlug: 'test-funnel',
      publishedAt: DateTime(2025, 1, 2),
      publishedVersion: 1,
    );

Future<void> _pumpScreen(WidgetTester tester, _FakeFunnelRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_SignedOutAuthRepository()),
        funnelRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: PublicFunnelViewScreen(slug: 'test-funnel'),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a loading indicator while the public funnel is being fetched', (tester) async {
    await _pumpScreen(tester, _FakeFunnelRepository());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the published funnel content once loaded', (tester) async {
    final repo = _FakeFunnelRepository()..view = _view();
    await _pumpScreen(tester, repo);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to the public page'), findsOneWidget);
    // A real anonymous visitor (no session) never sees the
    // owner-preview banner.
    expect(find.textContaining('PUBLIC PUBLISHED VERSION'), findsNothing);
  });

  testWidgets('shows a not-found state for a null result (draft/unpublished/nonexistent slug alike)',
      (tester) async {
    final repo = _FakeFunnelRepository()..view = null;
    await _pumpScreen(tester, repo);
    await tester.pumpAndSettle();

    expect(find.text('Funnel not found'), findsOneWidget);
  });

  testWidgets('shows a retryable error state on a genuine failure, distinct from not-found', (tester) async {
    final repo = _FakeFunnelRepository()..throwOnGet = true;
    await _pumpScreen(tester, repo);
    await tester.pumpAndSettle();

    expect(find.text('Funnel not found'), findsNothing);
    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
