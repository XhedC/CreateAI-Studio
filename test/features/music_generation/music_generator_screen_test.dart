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
import 'package:createai_studio/features/generation/data/models/generation_model.dart';
import 'package:createai_studio/features/generation/presentation/providers/generation_providers.dart';
import 'package:createai_studio/features/music_generation/presentation/screens/music_generator_screen.dart';

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

/// Lets each test drive the Create controller's [AsyncValue] directly,
/// instead of exercising the real Edge Function call - mirrors
/// image_generator_screen_test.dart's fake.
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
          return const MaterialApp(home: MusicGeneratorScreen());
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

    expect(find.text('AI Music Generator'), findsOneWidget);
    expect(find.text('Generate Music'), findsOneWidget);
    expect(find.text('Music Settings'), findsOneWidget);
    expect(find.textContaining('Enter lyrics or let AI create lyrics'), findsOneWidget);
  });

  testWidgets('shows a validation error for an empty prompt', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('Generate Music'));
    await tester.pumpAndSettle();

    expect(find.text('Please describe the music you want to create.'), findsOneWidget);
  });

  testWidgets('disables the lyrics field when "generate automatically" is on', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final lyricsField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'AI will write lyrics for you...'),
    );
    expect(lyricsField.enabled, isFalse);
  });

  testWidgets('shows the processing label while a generation is in progress', (tester) async {
    final container = await _pumpScreen(tester);

    final fakeController = container.read(createGenerationControllerProvider.notifier)
        as _FakeCreateGenerationController;
    fakeController.emit(const AsyncLoading());
    await tester.pump();

    expect(find.text('Creating your music...'), findsOneWidget);
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
