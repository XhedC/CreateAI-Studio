import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/user_settings_model.dart';

abstract class SettingsRepository {
  Future<Result<UserSettingsModel>> getSettings(String userId);
  Future<Result<UserSettingsModel>> updateSettings(
    String userId, {
    String? themeMode,
    String? language,
    bool? notificationsEnabled,
  });
}

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'user_settings';

  @override
  Future<Result<UserSettingsModel>> getSettings(String userId) async {
    try {
      final row =
          await _client.from(_table).select().eq('user_id', userId).single();
      return Result.success(UserSettingsModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<UserSettingsModel>> updateSettings(
    String userId, {
    String? themeMode,
    String? language,
    bool? notificationsEnabled,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .update({
            if (themeMode != null) 'theme_mode': themeMode,
            if (language != null) 'language': language,
            if (notificationsEnabled != null)
              'notifications_enabled': notificationsEnabled,
          })
          .eq('user_id', userId)
          .select()
          .single();
      return Result.success(UserSettingsModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
