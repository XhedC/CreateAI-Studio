import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/notification_model.dart';

abstract class NotificationRepository {
  Future<Result<List<NotificationModel>>> getNotifications(String userId);
  Future<Result<void>> markAsRead(String id);
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'notifications';

  @override
  Future<Result<List<NotificationModel>>> getNotifications(String userId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return Result.success(
        (rows as List).map((r) => NotificationModel.fromJson(r)).toList(),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> markAsRead(String id) async {
    try {
      await _client.from(_table).update({'is_read': true}).eq('id', id);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
