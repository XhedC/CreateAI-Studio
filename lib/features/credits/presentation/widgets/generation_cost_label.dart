import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/credits_providers.dart';

/// "N credits" text sourced from the `credit_costs` table (via
/// [creditCostsProvider]) - shown next to a Generate button so the user
/// knows the cost before submitting. This is a DISPLAY ONLY hint: the
/// backend independently looks up and enforces the real cost when the
/// request is made, so a stale or missing value here can never let a
/// generation through for the wrong price. See
/// docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
class GenerationCostLabel extends ConsumerWidget {
  const GenerationCostLabel({super.key, required this.generationType, this.multiplier = 1});

  final String generationType;

  /// For generation types priced per-unit (e.g. image cost is per image,
  /// multiplied by the number of images requested).
  final int multiplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costsAsync = ref.watch(creditCostsProvider);
    return costsAsync.maybeWhen(
      data: (costs) {
        final cost = costs[generationType];
        if (cost == null) return const SizedBox.shrink();
        final total = cost.cost * multiplier;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$total credit${total == 1 ? '' : 's'} per generation',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
