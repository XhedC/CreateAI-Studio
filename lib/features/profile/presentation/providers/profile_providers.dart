import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/profile_model.dart';
import '../../data/repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SupabaseProfileRepository(ref.watch(supabaseClientProvider));
});

final profileProvider = FutureProvider.autoDispose<ProfileModel?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final result = await ref.read(profileRepositoryProvider).getProfile(user.id);
  return result.when(success: (p) => p, failure: (_) => null);
});

class ProfileController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> updateProfile({String? fullName, String? avatarUrl}) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return false;
    state = const AsyncLoading();
    final result = await ref.read(profileRepositoryProvider).updateProfile(
          user.id,
          fullName: fullName,
          avatarUrl: avatarUrl,
        );
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        ref.invalidate(profileProvider);
        return true;
      },
      failure: (error) {
        state = AsyncError(error, StackTrace.current);
        return false;
      },
    );
  }
}

final profileControllerProvider = AsyncNotifierProvider<ProfileController, void>(
  ProfileController.new,
);
