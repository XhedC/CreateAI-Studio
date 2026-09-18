import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/constants/creation_type.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/auth/data/models/app_user.dart';
import 'package:createai_studio/features/auth/data/repositories/auth_repository.dart';
import 'package:createai_studio/features/auth/presentation/providers/auth_providers.dart';
import 'package:createai_studio/features/credits/data/models/credit_summary.dart';
import 'package:createai_studio/features/credits/data/repositories/credits_repository.dart';
import 'package:createai_studio/features/credits/presentation/providers/credits_providers.dart';
import 'package:createai_studio/features/funnel_generation/presentation/screens/funnel_generator_screen.dart';
import 'package:createai_studio/features/generation/data/models/generation_model.dart';
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

class _FakeCreditsRepository implements CreditsRepository {
  @override
  Future<Result<CreditSummary>> getSummary(String userId) async =>
      const Result.success(CreditSummary(planName: 'Free', creditsLimit: 50, creditsUsed: 10));
}

class _FakeCreateGenerationController extends CreateGenerationController {
  @override
  Future<GenerationModel?> build() async => null;

  void emit(AsyncValue<GenerationModel?> value) => state = value;

  @override
  Future<bool> submit({
    required CreationType type,
    required String prompt,
    String? projectId,
    List<String> attachmentUrls = const [],
    Map<String, dynamic> options = const {},
  }) async {
    return false;
  }
}

Future<ProviderContainer> _pumpScreen(WidgetTester tester) async {
  // This form is long (business info + funnel type + goal + two image
  // pickers) - tall enough that the Generate button would be off-screen/
  // unbuilt in the default test viewport. Use a tall viewport instead of
  // scrolling, so every test can find/tap it directly.
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        creditsRepositoryProvider.overrideWithValue(_FakeCreditsRepository()),
        createGenerationControllerProvider.overrideWith(_FakeCreateGenerationController.new),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const MaterialApp(home: FunnelGeneratorScreen());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders the initial (empty) state', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('AI Funnel Builder'), findsOneWidget);
    expect(find.text('Generate Funnel'), findsOneWidget);
    expect(find.text('Business information (optional)'), findsOneWidget);
    expect(find.text('Funnel type'), findsOneWidget);
    expect(find.text('Main goal'), findsOneWidget);
  });

  testWidgets('shows a validation error for an empty prompt', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('Generate Funnel'));
    await tester.pumpAndSettle();

    expect(find.text('Please describe the funnel you want to create.'), findsOneWidget);
  });

  testWidgets('shows the loading state while a generation is in progress', (tester) async {
    final container = await _pumpScreen(tester);

    final fakeController = container.read(createGenerationControllerProvider.notifier)
        as _FakeCreateGenerationController;
    fakeController.emit(const AsyncLoading());
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows a snackbar with the friendly message on failure', (tester) async {
    final container = await _pumpScreen(tester);

    final fakeController = container.read(createGenerationControllerProvider.notifier)
        as _FakeCreateGenerationController;
    fakeController.emit(
      AsyncError(
        const GenerationException(message: "You don't have enough credits for this generation."),
        StackTrace.current,
      ),
    );
    await tester.pump();

    expect(find.text("You don't have enough credits for this generation."), findsOneWidget);
  });
}
