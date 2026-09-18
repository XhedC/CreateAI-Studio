import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/credit_summary.dart';
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
