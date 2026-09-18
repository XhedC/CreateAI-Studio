import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/credit_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/generation_card.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../../core/widgets/project_card.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../credits/presentation/providers/credits_providers.dart';
import '../../../generation/presentation/providers/generation_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../widgets/quick_create_row.dart';
import '../widgets/welcome_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final creditsAsync = ref.watch(creditSummaryProvider);
    final recentGenerationsAsync = ref.watch(recentGenerationsProvider);
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push(RoutePaths.notifications),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(creditSummaryProvider);
          ref.invalidate(recentGenerationsProvider);
          await ref.read(projectsProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            WelcomeHeader(name: user?.displayName ?? 'there'),
            const SizedBox(height: 20),
            creditsAsync.when(
              data: (summary) => CreditCard(
                creditsRemaining: summary.creditsRemaining,
                planName: summary.planName,
                onTap: () => context.push(RoutePaths.usageDashboard),
              ),
              loading: () => const LoadingWidget(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            Text(
              'Quick Create',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            QuickCreateRow(
              onSelected: (type) {
                if (type == CreationType.image) {
                  context.push(RoutePaths.createImage);
                  return;
                }
                if (type == CreationType.music) {
                  context.push(RoutePaths.createMusic);
                  return;
                }
                if (type == CreationType.video) {
                  context.push(RoutePaths.createVideo);
                  return;
                }
                if (type == CreationType.funnel) {
                  context.push(RoutePaths.createFunnel);
                  return;
                }
                ref.read(pendingCreationTypeProvider.notifier).set(type);
                context.go(RoutePaths.create);
              },
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Recent Creations',
              onSeeAll: () => context.go(RoutePaths.history),
            ),
            const SizedBox(height: 10),
            recentGenerationsAsync.when(
              data: (generations) {
                if (generations.isEmpty) {
                  return const EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: 'No creations yet',
                    message: 'Start your first AI generation above.',
                  );
                }
                return Column(
                  children: [
                    for (final generation in generations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GenerationCard(
                          prompt: generation.prompt,
                          generationType: generation.generationType,
                          status: generation.status,
                          createdAt: generation.createdAt,
                          thumbnailUrl: generation.thumbnailUrl,
                          onTap: () => context
                              .push(RoutePaths.generationDetail(generation.id)),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const LoadingWidget(),
              error: (_, __) => const AppErrorWidget(),
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Recent Projects',
              onSeeAll: () => context.go(RoutePaths.projects),
            ),
            const SizedBox(height: 10),
            projectsAsync.when(
              data: (projects) {
                if (projects.isEmpty) {
                  return const EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'No projects yet',
                    message: 'Create a project to organize your generations.',
                  );
                }
                return Column(
                  children: [
                    for (final project in projects.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ProjectCard(
                          name: project.name,
                          projectType: project.projectType,
                          updatedAt: project.updatedAt,
                          description: project.description,
                          onTap: () =>
                              context.push(RoutePaths.projectDetail(project.id)),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const LoadingWidget(),
              error: (_, __) => const AppErrorWidget(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ],
    );
  }
}
