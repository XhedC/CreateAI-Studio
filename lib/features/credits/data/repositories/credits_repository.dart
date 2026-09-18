import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/credit_summary.dart';

abstract class CreditsRepository {
  Future<Result<CreditSummary>> getSummary(String userId);
}

class SupabaseCreditsRepository implements CreditsRepository {
  SupabaseCreditsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Result<CreditSummary>> getSummary(String userId) async {
    try {
      final row = await _client
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      if (row == null) return const Result.success(CreditSummary.fallback);
      return Result.success(CreditSummary.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
