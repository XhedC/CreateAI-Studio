import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:createai_studio/features/auth/data/repositories/auth_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

User _fakeUser(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime(2025, 1, 1).toIso8601String(),
    );

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
  });

  group('SupabaseAuthRepository.authStateChanges', () {
    // Regression test for the Splash -> Login startup hang: the router
    // reads this stream's first value to decide whether to redirect to
    // /login. Before this fix, the stream only ever forwarded
    // onAuthStateChange, so if that event was ever slow or never arrived,
    // the app was stuck on Splash forever even though `currentUser` was
    // already known synchronously.
    test('yields the current user immediately, even if onAuthStateChange never emits', () async {
      when(() => auth.currentUser).thenReturn(_fakeUser('user-1'));
      when(() => auth.onAuthStateChange).thenAnswer((_) => const Stream.empty());

      final repo = SupabaseAuthRepository(client);

      final firstValue =
          await repo.authStateChanges.first.timeout(const Duration(seconds: 2));

      expect(firstValue?.id, 'user-1');
    });

    test('yields null immediately when there is no signed-in user', () async {
      when(() => auth.currentUser).thenReturn(null);
      when(() => auth.onAuthStateChange).thenAnswer((_) => const Stream.empty());

      final repo = SupabaseAuthRepository(client);

      final firstValue =
          await repo.authStateChanges.first.timeout(const Duration(seconds: 2));

      expect(firstValue, isNull);
    });

    test('continues forwarding later onAuthStateChange events after the seeded value', () async {
      when(() => auth.currentUser).thenReturn(null);
      when(() => auth.onAuthStateChange).thenAnswer(
        (_) => Stream.value(
          AuthState(AuthChangeEvent.signedIn, Session(
            accessToken: 'token',
            tokenType: 'bearer',
            user: _fakeUser('user-2'),
          )),
        ),
      );

      final repo = SupabaseAuthRepository(client);

      final values = await repo.authStateChanges.take(2).toList();

      expect(values[0], isNull); // seeded currentUser (signed out)
      expect(values[1]?.id, 'user-2'); // real sign-in event afterward
    });
  });
}
