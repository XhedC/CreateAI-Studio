import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/credit_card.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../credits/presentation/providers/credits_providers.dart';
import '../providers/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final profileAsync = ref.watch(profileProvider);
    final creditsAsync = ref.watch(creditSummaryProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(RoutePaths.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: colors.primaryContainer,
                  backgroundImage: profileAsync.value?.avatarUrl != null
                      ? NetworkImage(profileAsync.value!.avatarUrl!)
                      : null,
                  child: profileAsync.value?.avatarUrl == null
                      ? Icon(Icons.person_rounded, size: 44, color: colors.onPrimaryContainer)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  user?.displayName ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          creditsAsync.when(
            data: (summary) => CreditCard(
              creditsRemaining: summary.creditsRemaining,
              planName: summary.planName,
              onTap: () => context.push(RoutePaths.usageDashboard),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Subscription'),
                  subtitle: Text(creditsAsync.value?.planName ?? 'Free'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.plans),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Credit History'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.creditHistory),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.settings),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.notifications),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Log out',
            variant: AppButtonVariant.outlined,
            icon: Icons.logout_rounded,
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }
}
