import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../../core/widgets/project_card.dart';
import '../../data/models/project_model.dart';
import '../providers/project_providers.dart';
import '../widgets/create_project_dialog.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final name = await showProjectNameDialog(context, title: 'New project');
    if (name == null || name.isEmpty) return;
    await ref.read(projectsProvider.notifier).createProject(name: name);
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    ProjectModel project,
    String action,
  ) async {
    switch (action) {
      case 'rename':
        final name = await showProjectNameDialog(
          context,
          title: 'Rename project',
          initialName: project.name,
        );
        if (name != null && name.isNotEmpty) {
          await ref
              .read(projectsProvider.notifier)
              .renameProject(project.id, name);
        }
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete project?'),
            content: Text(
              'This will permanently delete "${project.name}". This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await ref.read(projectsProvider.notifier).deleteProject(project.id);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createProject(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: projectsAsync.when(
        loading: () => const LoadingWidget(),
        error: (error, _) => AppErrorWidget(
          onRetry: () => ref.read(projectsProvider.notifier).refresh(),
        ),
        data: (projects) {
          if (projects.isEmpty) {
            return EmptyState(
              icon: Icons.folder_open_rounded,
              title: 'No projects yet',
              message: 'Create a project to organize your AI generations.',
              actionLabel: 'New project',
              onAction: () => _createProject(context, ref),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(projectsProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final project = projects[index];
                return ProjectCard(
                  name: project.name,
                  projectType: project.projectType,
                  updatedAt: project.updatedAt,
                  description: project.description,
                  thumbnailUrl: project.thumbnailUrl,
                  onTap: () =>
                      context.push(RoutePaths.projectDetail(project.id)),
                  onMorePressed: () => showModalBottomSheet(
                    context: context,
                    builder: (sheetContext) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.edit_outlined),
                            title: const Text('Rename'),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              _handleMenu(context, ref, project, 'rename');
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete_outline_rounded),
                            title: const Text('Delete'),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              _handleMenu(context, ref, project, 'delete');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
