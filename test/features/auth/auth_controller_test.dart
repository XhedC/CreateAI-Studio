import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/auth/data/models/app_user.dart';
import 'package:createai_studio/features/auth/data/repositories/auth_repository.dart';
import 'package:createai_studio/features/auth/presentation/providers/auth_providers.dart';

/// In-memory fake so auth flows can be tested without hitting Supabase.
class FakeAuthRepository implements AuthRepository {
  AppUser? _currentUser;
  bool failNextCall = false;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Stream<AppUser?> get authStateChanges => Stream.value(_currentUser);

  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) async {
    if (failNextCall) {
      return const Result.failure(AuthException('The email or password you entered is incorrect.'));
    }
    _currentUser = AppUser(id: 'user-1', email: email);
    return Result.success(_currentUser!);
  }

  @override
  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    if (failNextCall) {
      return const Result.failure(AuthException('An account with this email already exists.'));
    }
    _currentUser = AppUser(id: 'user-1', email: email, fullName: fullName);
    return Result.success(_currentUser!);
  }

  @override
  Future<Result<void>> signOut() async {
    _currentUser = null;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    if (failNextCall) {
      return const Result.failure(AuthException('We could not complete that request.'));
    }
    return const Result.success(null);
  }
}

void main() {
  late FakeAuthRepository fakeRepository;
  late ProviderContainer container;

  setUp(() {
    fakeRepository = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(fakeRepository)],
    );
    addTearDown(container.dispose);
  });

  test('signIn succeeds and exposes AsyncData', () async {
    final ok = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'user@example.com', password: 'password123');

    expect(ok, isTrue);
    expect(container.read(authControllerProvider).hasError, isFalse);
    expect(fakeRepository.currentUser?.email, 'user@example.com');
  });

  test('signIn failure surfaces a friendly AppException via AsyncError', () async {
    fakeRepository.failNextCall = true;

    final ok = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'user@example.com', password: 'wrong');

    expect(ok, isFalse);
    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<AppException>());
  });

  test('signUp creates a user and signOut clears it', () async {
    await container.read(authControllerProvider.notifier).signUp(
          email: 'new@example.com',
          password: 'password123',
          fullName: 'New User',
        );
    expect(fakeRepository.currentUser, isNotNull);

    await container.read(authControllerProvider.notifier).signOut();
    expect(fakeRepository.currentUser, isNull);
  });
}
