import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/credit_cost.dart';
import '../../data/models/credit_summary.dart';
import '../../data/models/credit_transaction.dart';
import '../../data/models/plan.dart';
import '../../data/models/usage_record.dart';
import '../../data/repositories/credits_repository.dart';

final creditsRepositoryProvider = Provider<CreditsRepository>((ref) {
  return SupabaseCreditsRepository(ref.watch(supabaseClientProvider));
});

final creditSummaryProvider = FutureProvider.autoDispose<CreditSummary>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return CreditSummary.fallback;
  final result = await ref.read(creditsRepositoryProvider).getSummary(user.id);
  return result.when(success: (s) => s, failure: (_) => CreditSummary.fallback);
});

/// All active plans, for the Plan/Subscription comparison screen.
final plansProvider = FutureProvider.autoDispose<List<Plan>>((ref) async {
  final result = await ref.read(creditsRepositoryProvider).getPlans();
  return result.when(success: (plans) => plans, failure: (_) => const []);
});

/// The current server-trusted cost of every generation type, keyed by
/// `generation_type` - generator screens read this to show "N credits"
/// before submitting. Never used to compute the actual charge.
final creditCostsProvider = FutureProvider.autoDispose<Map<String, CreditCost>>((ref) async {
  final result = await ref.read(creditsRepositoryProvider).getCreditCosts();
  return result.when(
    success: (costs) => {for (final c in costs) c.generationType: c},
    failure: (_) => const {},
  );
});

/// One page of the signed-in user's own credit ledger, newest first.
final creditTransactionsProvider = FutureProvider.autoDispose
    .family<List<CreditTransaction>, ({int limit, int offset})>((ref, page) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  final result = await ref
      .read(creditsRepositoryProvider)
      .getCreditTransactions(user.id, limit: page.limit, offset: page.offset);
  return result.when(success: (txns) => txns, failure: (_) => const []);
});

/// Accumulated, "load more"-style paging over the credit ledger for the
/// Credit History screen - simpler than infinite-scroll bookkeeping while
/// still avoiding an unbounded single query.
class CreditHistoryController extends AsyncNotifier<List<CreditTransaction>> {
  static const int pageSize = 20;

  int _offset = 0;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  Future<List<CreditTransaction>> build() async {
    _offset = 0;
    _hasMore = true;
    return _fetchNextPage(const []);
  }

  Future<void> loadMore() async {
    if (state.isLoading || !_hasMore) return;
    final current = state.value ?? const [];
    state = await AsyncValue.guard(() => _fetchNextPage(current));
  }

  Future<void> refresh() async {
    _offset = 0;
    _hasMore = true;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchNextPage(const []));
  }

  Future<List<CreditTransaction>> _fetchNextPage(
    List<CreditTransaction> existing,
  ) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return existing;
    final result = await ref
        .read(creditsRepositoryProvider)
        .getCreditTransactions(user.id, limit: pageSize, offset: _offset);
    return result.when(
      success: (page) {
        _offset += page.length;
        _hasMore = page.length == pageSize;
        return [...existing, ...page];
      },
      failure: (_) {
        _hasMore = false;
        return existing;
      },
    );
  }
}

final creditHistoryControllerProvider =
    AsyncNotifierProvider<CreditHistoryController, List<CreditTransaction>>(
  CreditHistoryController.new,
);

/// Recent usage events for the Usage Dashboard's per-type breakdown.
final usageRecordsProvider = FutureProvider.autoDispose<List<UsageRecord>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  final result = await ref.read(creditsRepositoryProvider).getUsageRecords(user.id);
  return result.when(success: (records) => records, failure: (_) => const []);
});
