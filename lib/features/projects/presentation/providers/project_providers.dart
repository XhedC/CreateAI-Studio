import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/project_model.dart';
import '../../data/repositories/project_repository.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return SupabaseProjectRepository(ref.watch(supabaseClientProvider));
});

/// Loads and mutates the current user's projects. Screens call
/// [createProject]/[renameProject]/[deleteProject] and this notifier
/// refreshes its own state so History/Home stay in sync without manual
/// invalidation wiring.
class ProjectsNotifier extends AsyncNotifier<List<ProjectModel>> {
  @override
  Future<List<ProjectModel>> build() async {
    final user = ref.watch(authStateProvider).value;
    if (user == null) return [];
    final result = await ref.read(projectRepositoryProvider).getProjects(user.id);
    return result.when(success: (data) => data, failure: (e) => throw e);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<bool> createProject({
    required String name,
    String? description,
    String projectType = 'general',
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return false;
    final result = await ref.read(projectRepositoryProvider).createProject(
          userId: user.id,
          name: name,
          description: description,
          projectType: projectType,
        );
    return result.when(
      success: (project) {
        state = AsyncData([project, ...state.value ?? []]);
        return true;
      },
      failure: (_) => false,
    );
  }

  Future<bool> renameProject(String projectId, String newName) async {
    final result =
        await ref.read(projectRepositoryProvider).renameProject(projectId, newName);
    return result.when(
      success: (updated) {
        final current = state.value ?? [];
        state = AsyncData([
          for (final p in current) p.id == updated.id ? updated : p,
        ]);
        return true;
      },
      failure: (_) => false,
    );
  }

  Future<bool> deleteProject(String projectId) async {
    final result = await ref.read(projectRepositoryProvider).deleteProject(projectId);
    return result.when(
      success: (_) {
        final current = state.value ?? [];
        state = AsyncData(current.where((p) => p.id != projectId).toList());
        return true;
      },
      failure: (_) => false,
    );
  }
}

final projectsProvider =
    AsyncNotifierProvider<ProjectsNotifier, List<ProjectModel>>(
  ProjectsNotifier.new,
);

/// Single-project lookup for the detail screen (falls back to a direct fetch
/// if the list provider hasn't loaded that project yet).
final projectByIdProvider =
    FutureProvider.family<ProjectModel?, String>((ref, projectId) async {
  final list = ref.watch(projectsProvider).value;
  if (list != null) {
    for (final p in list) {
      if (p.id == projectId) return p;
    }
  }
  final result = await ref.read(projectRepositoryProvider).getProject(projectId);
  return result.when(success: (p) => p, failure: (_) => null);
});
