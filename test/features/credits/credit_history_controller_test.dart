import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/auth/data/models/app_user.dart';
import 'package:createai_studio/features/auth/data/repositories/auth_repository.dart';
import 'package:createai_studio/features/auth/presentation/providers/auth_providers.dart';
import 'package:createai_studio/features/credits/data/models/credit_cost.dart';
import 'package:createai_studio/features/credits/data/models/credit_summary.dart';
import 'package:createai_studio/features/credits/data/models/credit_transaction.dart';
import 'package:createai_studio/features/credits/data/models/plan.dart';
import 'package:createai_studio/features/credits/data/models/usage_record.dart';
import 'package:createai_studio/features/credits/data/repositories/credits_repository.dart';
import 'package:createai_studio/features/credits/presentation/providers/credits_providers.dart';

class _FakeAuthRepository implements AuthRepository {
  final _user = const AppUser(id: 'user-1', email: 'user@example.com');
  @override
  AppUser? get currentUser => _user;
  @override
  Stream<AppUser?> get authStateChanges => Stream.value(_user);
  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) async =>
      Result.success(_user);
  @override
  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async =>
      Result.success(_user);
  @override
  Future<Result<void>> signOut() async => const Result.success(null);
  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async => const Result.success(null);
}

CreditTransaction _tx(int i) => CreditTransaction(
      id: 'tx-$i',
      amount: -1,
      transactionType: 'GENERATION_CHARGE',
      createdAt: DateTime(2025, 1, 1).subtract(Duration(minutes: i)),
    );

/// In-memory fake backed by a fixed-size ledger, so the controller's
/// "load more" paging logic can be exercised without a live Supabase query.
class _FakeCreditsRepository implements CreditsRepository {
  _FakeCreditsRepository(this.ledgerSize);
  final int ledgerSize;

  @override
  Future<Result<CreditSummary>> getSummary(String userId) async =>
      const Result.success(CreditSummary.fallback);
  @override
  Future<Result<List<Plan>>> getPlans() async => const Result.success([]);
  @override
  Future<Result<List<CreditCost>>> getCreditCosts() async => const Result.success([]);
  @override
  Future<Result<List<UsageRecord>>> getUsageRecords(String userId, {int limit = 200}) async =>
      const Result.success([]);

  @override
  Future<Result<List<CreditTransaction>>> getCreditTransactions(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final all = List.generate(ledgerSize, _tx);
    if (offset >= all.length) return const Result.success([]);
    final end = (offset + limit).clamp(0, all.length);
    return Result.success(all.sublist(offset, end));
  }
}

void main() {
  late ProviderContainer container;

  ProviderContainer buildContainer(int ledgerSize) {
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        creditsRepositoryProvider.overrideWithValue(_FakeCreditsRepository(ledgerSize)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(authStateProvider, (_, __) {});
    return c;
  }

  test('build() loads the first page and reports hasMore when a full page came back', () async {
    container = buildContainer(50);
    await container.read(authStateProvider.future);
    final notifier = container.read(creditHistoryControllerProvider.notifier);

    final first = await container.read(creditHistoryControllerProvider.future);

    expect(first, hasLength(CreditHistoryController.pageSize));
    expect(notifier.hasMore, isTrue);
  });

  test('loadMore appends the next page and stops when the ledger is exhausted', () async {
    container = buildContainer(25);
    await container.read(authStateProvider.future);
    final notifier = container.read(creditHistoryControllerProvider.notifier);

    await container.read(creditHistoryControllerProvider.future);
    await notifier.loadMore();

    final all = container.read(creditHistoryControllerProvider).value!;
    expect(all, hasLength(25));
    expect(notifier.hasMore, isFalse);

    // A further loadMore() call is a no-op once hasMore is false.
    await notifier.loadMore();
    expect(container.read(creditHistoryControllerProvider).value, hasLength(25));
  });

  test('refresh() resets back to the first page', () async {
    container = buildContainer(50);
    await container.read(authStateProvider.future);
    final notifier = container.read(creditHistoryControllerProvider.notifier);

    await container.read(creditHistoryControllerProvider.future);
    await notifier.loadMore();
    expect(container.read(creditHistoryControllerProvider).value, hasLength(40));

    await notifier.refresh();
    expect(
      container.read(creditHistoryControllerProvider).value,
      hasLength(CreditHistoryController.pageSize),
    );
  });
}
