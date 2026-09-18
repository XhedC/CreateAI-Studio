import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

/// Live authentication state - the single source of truth the router and
/// every screen use to know whether a user is signed in.
final authStateProvider = StreamProvider<AppUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});

/// Drives the login/register/forgot-password forms: exposes an [AsyncValue]
/// so screens can show a spinner while pending and a friendly error message
/// on failure, without duplicating that logic per screen.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<bool> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    final result = await _repo.signIn(email: email, password: password);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (error) {
        state = AsyncError(error, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.signUp(
      email: email,
      password: password,
      fullName: fullName,
    );
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (error) {
        state = AsyncError(error, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> sendPasswordReset(String email) async {
    state = const AsyncLoading();
    final result = await _repo.sendPasswordResetEmail(email);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (error) {
        state = AsyncError(error, StackTrace.current);
        return false;
      },
    );
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    final result = await _repo.signOut();
    state = result.when(
      success: (_) => const AsyncData(null),
      failure: (error) => AsyncError(error, StackTrace.current),
    );
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
