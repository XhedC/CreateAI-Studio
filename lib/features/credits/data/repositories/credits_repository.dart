import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/credit_cost.dart';
import '../models/credit_summary.dart';
import '../models/credit_transaction.dart';
import '../models/plan.dart';
import '../models/usage_record.dart';

abstract class CreditsRepository {
  Future<Result<CreditSummary>> getSummary(String userId);

  /// All active plans, ordered by monthly credit allowance - for the
  /// Plan/Subscription comparison screen. DB-driven so limits/pricing can
  /// change without an app release.
  Future<Result<List<Plan>>> getPlans();

  /// The current, server-trusted cost of every active generation type - so
  /// generator screens can display "Generate Video - 5 credits" before
  /// submitting. Never used to compute the actual charge (the backend does
  /// that independently and is the only source of truth).
  Future<Result<List<CreditCost>>> getCreditCosts();

  /// One page of the caller's own credit ledger, newest first.
  Future<Result<List<CreditTransaction>>> getCreditTransactions(
    String userId, {
    int limit = 20,
    int offset = 0,
  });

  /// The caller's own recent billable generation events, newest first - for
  /// the Usage Dashboard's per-type breakdown.
  Future<Result<List<UsageRecord>>> getUsageRecords(String userId, {int limit = 200});
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

  @override
  Future<Result<List<Plan>>> getPlans() async {
    try {
      final rows = await _client
          .from('plans')
          .select()
          .eq('active', true)
          .order('monthly_credits', ascending: true);
      return Result.success((rows as List).map((r) => Plan.fromJson(r)).toList());
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<List<CreditCost>>> getCreditCosts() async {
    try {
      final rows = await _client.from('credit_costs').select().eq('active', true);
      return Result.success((rows as List).map((r) => CreditCost.fromJson(r)).toList());
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<List<CreditTransaction>>> getCreditTransactions(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client
          .from('credit_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return Result.success(
        (rows as List).map((r) => CreditTransaction.fromJson(r)).toList(),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<List<UsageRecord>>> getUsageRecords(String userId, {int limit = 200}) async {
    try {
      final rows = await _client
          .from('usage_records')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return Result.success((rows as List).map((r) => UsageRecord.fromJson(r)).toList());
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
