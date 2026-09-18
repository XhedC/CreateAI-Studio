import 'package:flutter/material.dart';

/// Home/Profile credit-balance summary card. Values are placeholders until
/// the Credits/Subscription phase wires up real usage tracking.
class CreditCard extends StatelessWidget {
  const CreditCard({
    super.key,
    required this.creditsRemaining,
    required this.planName,
    this.onTap,
  });

  final int creditsRemaining;
  final String planName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.onPrimaryContainer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bolt_rounded, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$creditsRemaining credits',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      '$planName plan',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: colors.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
