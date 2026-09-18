import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/notification_model.dart';
import '../../data/repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return SupabaseNotificationRepository(ref.watch(supabaseClientProvider));
});

final notificationsProvider =
    FutureProvider.autoDispose<List<NotificationModel>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final result = await ref.read(notificationRepositoryProvider).getNotifications(user.id);
  return result.when(success: (data) => data, failure: (_) => []);
});
