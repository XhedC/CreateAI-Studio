import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../data/models/credit_transaction.dart';
import '../providers/credits_providers.dart';

/// The full, auditable credit ledger for the signed-in user - every grant,
/// charge, and refund the backend has ever recorded for their account.
/// Read-only: nothing on this screen can write to `credit_transactions`.
class CreditHistoryScreen extends ConsumerWidget {
  const CreditHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(creditHistoryControllerProvider);
    final controller = ref.read(creditHistoryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Credit History')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: historyAsync.when(
          loading: () => const LoadingWidget(),
          error: (_, __) => AppErrorWidget(onRetry: controller.refresh),
          data: (transactions) {
            if (transactions.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No credit activity yet',
                message: 'Your credit grants, charges, and refunds will show up here.',
              );
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 200) {
                  controller.loadMore();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                itemCount: transactions.length + (controller.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index >= transactions.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    );
                  }
                  return _TransactionTile(transaction: transactions[index]);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final CreditTransaction transaction;

  static const Map<String, String> _typeLabels = {
    'MONTHLY_GRANT': 'Monthly credit grant',
    'GENERATION_CHARGE': 'Generation',
    'REFUND': 'Refund',
    'MANUAL_ADJUSTMENT': 'Manual adjustment',
    'PURCHASE': 'Credit purchase',
    'SUBSCRIPTION_GRANT': 'Subscription credit grant',
    'EXPIRATION': 'Credit expiration',
    'PROMOTIONAL_CREDIT': 'Promotional credit',
  };

  static const Map<String, IconData> _typeIcons = {
    'MONTHLY_GRANT': Icons.calendar_month_rounded,
    'GENERATION_CHARGE': Icons.auto_awesome_rounded,
    'REFUND': Icons.replay_rounded,
    'MANUAL_ADJUSTMENT': Icons.tune_rounded,
    'PURCHASE': Icons.shopping_cart_rounded,
    'SUBSCRIPTION_GRANT': Icons.workspace_premium_rounded,
    'EXPIRATION': Icons.timer_off_rounded,
    'PROMOTIONAL_CREDIT': Icons.card_giftcard_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isCredit = transaction.isCredit;
    final label = _typeLabels[transaction.transactionType] ?? transaction.transactionType;
    final icon = _typeIcons[transaction.transactionType] ?? Icons.receipt_outlined;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCredit ? colors.primaryContainer : colors.surfaceContainerHighest,
        child: Icon(
          icon,
          size: 20,
          color: isCredit ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        ),
      ),
      title: Text(label),
      subtitle: Text(
        transaction.description ?? DateFormatter.full(transaction.createdAt.toLocal()),
      ),
      trailing: Text(
        '${isCredit ? '+' : ''}${transaction.amount}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isCredit ? colors.primary : colors.error,
            ),
      ),
    );
  }
}
