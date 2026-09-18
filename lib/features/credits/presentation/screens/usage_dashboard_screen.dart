import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../data/models/credit_summary.dart';
import '../../data/models/usage_record.dart';
import '../providers/credits_providers.dart';

/// Read-only overview of the signed-in user's plan, credit balance, and
/// recent usage by generation type. Everything shown here is what the
/// backend already computed (`subscriptions`/`usage_records`) - this screen
/// never computes or displays a cost/balance the server hasn't confirmed.
class UsageDashboardScreen extends ConsumerWidget {
  const UsageDashboardScreen({super.key});

  static const Map<String, String> _typeLabels = {
    'text': 'Text',
    'image': 'Image',
    'music': 'Music',
    'video': 'Video',
    'funnel': 'Funnel',
  };

  static const Map<String, IconData> _typeIcons = {
    'text': Icons.text_fields_rounded,
    'image': Icons.image_outlined,
    'music': Icons.music_note_rounded,
    'video': Icons.videocam_outlined,
    'funnel': Icons.web_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(creditSummaryProvider);
    final usageAsync = ref.watch(usageRecordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Credit history',
            onPressed: () => context.push(RoutePaths.creditHistory),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(creditSummaryProvider);
          ref.invalidate(usageRecordsProvider);
        },
        child: summaryAsync.when(
          loading: () => const LoadingWidget(),
          error: (_, __) => AppErrorWidget(
            onRetry: () => ref.invalidate(creditSummaryProvider),
          ),
          data: (summary) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BalanceCard(summary: summary),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Usage by type',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: () => context.push(RoutePaths.plans),
                    child: const Text('View plans'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              usageAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: LoadingWidget(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (records) => _UsageBreakdown(records: records),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});

  final CreditSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ratio = summary.creditsLimit == 0
        ? 0.0
        : (summary.creditsUsed / summary.creditsLimit).clamp(0.0, 1.0);

    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${summary.planName} plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onPrimaryContainer,
                      ),
                ),
                Icon(Icons.bolt_rounded, color: colors.onPrimaryContainer),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.creditsRemaining} of ${summary.creditsLimit} credits remaining',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.9),
                  ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: colors.onPrimaryContainer.withValues(alpha: 0.15),
                color: colors.onPrimaryContainer,
              ),
            ),
            if (summary.currentPeriodEnd != null) ...[
              const SizedBox(height: 10),
              Text(
                'Renews ${DateFormatter.short(summary.currentPeriodEnd!.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Lifetime: ${summary.lifetimeCreditsEarned} earned · '
              '${summary.lifetimeCreditsUsed} used',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageBreakdown extends StatelessWidget {
  const _UsageBreakdown({required this.records});

  final List<UsageRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No generations yet - your usage will show up here once you '
          'create something.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final byType = <String, ({int count, int credits})>{};
    for (final record in records) {
      if (record.status == 'refunded') continue;
      final existing = byType[record.generationType] ?? (count: 0, credits: 0);
      byType[record.generationType] = (
        count: existing.count + 1,
        credits: existing.credits + record.creditsConsumed,
      );
    }
    final entries = byType.entries.toList()
      ..sort((a, b) => b.value.credits.compareTo(a.value.credits));

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: Icon(
                UsageDashboardScreen._typeIcons[entries[i].key] ?? Icons.auto_awesome_outlined,
              ),
              title: Text(
                UsageDashboardScreen._typeLabels[entries[i].key] ?? entries[i].key,
              ),
              subtitle: Text('${entries[i].value.count} generations'),
              trailing: Text(
                '${entries[i].value.credits} credits',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
