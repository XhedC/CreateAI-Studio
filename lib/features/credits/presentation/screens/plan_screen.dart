import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../data/models/plan.dart';
import '../providers/credits_providers.dart';

/// Free/Pro/Business plan comparison. No real payment processing exists yet
/// (Phase 6 is billing *foundation* only) - selecting a paid plan shows a
/// "coming soon" message rather than a fake successful upgrade. Plan names,
/// credit limits, and descriptions are all read from the `plans` table, not
/// hardcoded here, so they can change without an app release.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansProvider);
    final currentSummary = ref.watch(creditSummaryProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Plans & Subscription')),
      body: plansAsync.when(
        loading: () => const LoadingWidget(),
        error: (_, __) => AppErrorWidget(
          onRetry: () => ref.invalidate(plansProvider),
        ),
        data: (plans) {
          if (plans.isEmpty) {
            return const AppErrorWidget(message: 'No plans are available right now.');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PlanCard(
                    plan: plan,
                    isCurrent: currentSummary?.planCode == plan.code,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Payment integration is coming in a future update. You will '
                'be able to upgrade or downgrade your plan here once it is '
                'available - no charge has been made.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isCurrent});

  final Plan plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final features = plan.features;

    return Card(
      color: isCurrent ? colors.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCurrent
            ? BorderSide(color: colors.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  plan.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? colors.onPrimaryContainer : null,
                      ),
                ),
                if (isCurrent)
                  Chip(
                    label: const Text('Current plan'),
                    backgroundColor: colors.primary,
                    labelStyle: TextStyle(color: colors.onPrimary),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${plan.monthlyCredits} credits / month',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? colors.onPrimaryContainer : null,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              plan.priceDisplay,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isCurrent
                        ? colors.onPrimaryContainer.withValues(alpha: 0.8)
                        : colors.onSurfaceVariant,
                  ),
            ),
            if (plan.description != null) ...[
              const SizedBox(height: 10),
              Text(
                plan.description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isCurrent
                          ? colors.onPrimaryContainer.withValues(alpha: 0.9)
                          : colors.onSurfaceVariant,
                    ),
              ),
            ],
            if (features['priority_support'] == true) ...[
              const SizedBox(height: 10),
              _FeatureRow(
                icon: Icons.support_agent_rounded,
                label: 'Priority support',
                emphasize: isCurrent,
              ),
            ],
            if (features['team_seats'] == true) ...[
              const SizedBox(height: 6),
              _FeatureRow(
                icon: Icons.group_rounded,
                label: 'Team seats',
                emphasize: isCurrent,
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: isCurrent
                  ? const OutlinedButton(
                      onPressed: null,
                      child: Text('Your current plan'),
                    )
                  : FilledButton(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Upgrading plans is coming in a future update.',
                          ),
                        ),
                      ),
                      child: Text('Select ${plan.name}'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label, required this.emphasize});

  final IconData icon;
  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = emphasize ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
