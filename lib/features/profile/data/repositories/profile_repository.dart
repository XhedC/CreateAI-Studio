import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/profile_model.dart';

abstract class ProfileRepository {
  Future<Result<ProfileModel>> getProfile(String userId);
  Future<Result<ProfileModel>> updateProfile(
    String userId, {
    String? fullName,
    String? avatarUrl,
  });
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'profiles';

  @override
  Future<Result<ProfileModel>> getProfile(String userId) async {
    try {
      final row =
          await _client.from(_table).select().eq('user_id', userId).single();
      return Result.success(ProfileModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<ProfileModel>> updateProfile(
    String userId, {
    String? fullName,
    String? avatarUrl,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .update({
            if (fullName != null) 'full_name': fullName,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
          })
          .eq('user_id', userId)
          .select()
          .single();
      return Result.success(ProfileModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
