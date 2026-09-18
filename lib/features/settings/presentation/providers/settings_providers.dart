import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/user_settings_model.dart';
import '../../data/repositories/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SupabaseSettingsRepository(ref.watch(supabaseClientProvider));
});

final userSettingsProvider = FutureProvider.autoDispose<UserSettingsModel?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final result = await ref.read(settingsRepositoryProvider).getSettings(user.id);
  return result.when(success: (s) => s, failure: (_) => null);
});

class UserSettingsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> setNotificationsEnabled(bool enabled) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .updateSettings(user.id, notificationsEnabled: enabled);
    ref.invalidate(userSettingsProvider);
  }

  Future<void> setLanguage(String language) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    await ref.read(settingsRepositoryProvider).updateSettings(user.id, language: language);
    ref.invalidate(userSettingsProvider);
  }
}

final userSettingsControllerProvider =
    AsyncNotifierProvider<UserSettingsController, void>(UserSettingsController.new);
