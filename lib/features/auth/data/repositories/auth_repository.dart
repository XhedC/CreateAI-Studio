import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/app_user.dart';

abstract class AuthRepository {
  Stream<AppUser?> get authStateChanges;
  AppUser? get currentUser;

  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  });

  Future<Result<AppUser>> signIn({
    required String email,
    required String password,
  });

  Future<Result<void>> signOut();

  Future<Result<void>> sendPasswordResetEmail(String email);
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    final metadata = user.userMetadata ?? const {};
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      fullName: metadata['full_name'] as String?,
      avatarUrl: metadata['avatar_url'] as String?,
    );
  }

  @override
  Stream<AppUser?> get authStateChanges async* {
    // `_client.auth.currentUser` is already populated synchronously by the
    // time `Supabase.initialize()` returns (it's set during session
    // recovery, before `main()` ever calls `runApp()`) - yielding it first
    // means the router's redirect logic never has to wait on
    // `onAuthStateChange`'s first event to know the answer it already has.
    // `onAuthStateChange` itself is a replay-to-late-subscribers stream, so
    // this does not skip or duplicate any real sign-in/sign-out event; it
    // only removes an unnecessary "loading" window on cold start.
    yield currentUser;
    yield* _client.auth.onAuthStateChange.map(
      (data) => _toAppUser(data.session?.user),
    );
  }

  @override
  AppUser? get currentUser => _toAppUser(_client.auth.currentUser);

  @override
  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      final user = _toAppUser(response.user);
      if (user == null) {
        return Result.failure(
          const AuthException('Registration could not be completed.'),
        );
      }
      return Result.success(user);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<AppUser>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = _toAppUser(response.user);
      if (user == null) {
        return Result.failure(const AuthException('Sign in failed.'));
      }
      return Result.success(user);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _client.auth.signOut();
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
