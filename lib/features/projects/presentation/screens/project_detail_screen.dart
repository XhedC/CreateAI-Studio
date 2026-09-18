import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/generation_card.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../generation/presentation/providers/generation_providers.dart';
import '../providers/project_providers.dart';
import '../widgets/create_project_dialog.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));
    final generationsAsync = ref.watch(generationsByProjectProvider(projectId));

    return Scaffold(
      appBar: AppBar(
        title: projectAsync.when(
          data: (project) => Text(project?.name ?? 'Project'),
          loading: () => const Text('Project'),
          error: (_, __) => const Text('Project'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final project = ref.read(projectByIdProvider(projectId)).value;
              if (project == null) return;
              final name = await showProjectNameDialog(
                context,
                title: 'Rename project',
                initialName: project.name,
              );
              if (name != null && name.isNotEmpty) {
                await ref
                    .read(projectsProvider.notifier)
                    .renameProject(projectId, name);
                ref.invalidate(projectByIdProvider(projectId));
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.create),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New generation'),
      ),
      body: projectAsync.when(
        loading: () => const LoadingWidget(),
        error: (_, __) => const AppErrorWidget(),
        data: (project) {
          if (project == null) {
            return const AppErrorWidget(message: 'This project could not be found.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (project.description != null && project.description!.isNotEmpty) ...[
                      Text(project.description!, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Created ${DateFormatter.short(project.createdAt)} - '
                      'Updated ${DateFormatter.relative(project.updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: generationsAsync.when(
                  loading: () => const LoadingWidget(),
                  error: (_, __) => AppErrorWidget(
                    onRetry: () => ref.invalidate(generationsByProjectProvider(projectId)),
                  ),
                  data: (generations) {
                    if (generations.isEmpty) {
                      return const EmptyState(
                        icon: Icons.auto_awesome_outlined,
                        title: 'No generations in this project yet',
                        message: 'Tap "New generation" to create your first one here.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: generations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final generation = generations[index];
                        return GenerationCard(
                          prompt: generation.prompt,
                          generationType: generation.generationType,
                          status: generation.status,
                          createdAt: generation.createdAt,
                          thumbnailUrl: generation.thumbnailUrl,
                          onTap: () => context
                              .push(RoutePaths.generationDetail(generation.id)),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
