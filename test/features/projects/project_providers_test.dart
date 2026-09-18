import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/auth/data/models/app_user.dart';
import 'package:createai_studio/features/auth/data/repositories/auth_repository.dart';
import 'package:createai_studio/features/auth/presentation/providers/auth_providers.dart';
import 'package:createai_studio/features/projects/data/models/project_model.dart';
import 'package:createai_studio/features/projects/data/repositories/project_repository.dart';
import 'package:createai_studio/features/projects/presentation/providers/project_providers.dart';

class FakeAuthRepository implements AuthRepository {
  final _user = const AppUser(id: 'user-1', email: 'user@example.com');

  @override
  AppUser? get currentUser => _user;
  @override
  Stream<AppUser?> get authStateChanges => Stream.value(_user);
  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) async =>
      Result.success(_user);
  @override
  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async =>
      Result.success(_user);
  @override
  Future<Result<void>> signOut() async => const Result.success(null);
  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async => const Result.success(null);
}

/// In-memory fake so project CRUD flows can be tested without Supabase.
class FakeProjectRepository implements ProjectRepository {
  final List<ProjectModel> _projects = [];
  int _idCounter = 0;

  @override
  Future<Result<List<ProjectModel>>> getProjects(String userId) async =>
      Result.success(List.unmodifiable(_projects));

  @override
  Future<Result<ProjectModel>> getProject(String projectId) async {
    for (final project in _projects) {
      if (project.id == projectId) return Result.success(project);
    }
    throw StateError('not found');
  }

  @override
  Future<Result<ProjectModel>> createProject({
    required String userId,
    required String name,
    String? description,
    String projectType = 'general',
  }) async {
    final project = ProjectModel(
      id: 'project-${_idCounter++}',
      userId: userId,
      name: name,
      description: description,
      projectType: projectType,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );
    _projects.insert(0, project);
    return Result.success(project);
  }

  @override
  Future<Result<ProjectModel>> renameProject(String projectId, String newName) async {
    final index = _projects.indexWhere((p) => p.id == projectId);
    final renamed = _projects[index].copyWith(name: newName);
    _projects[index] = renamed;
    return Result.success(renamed);
  }

  @override
  Future<Result<void>> deleteProject(String projectId) async {
    _projects.removeWhere((p) => p.id == projectId);
    return const Result.success(null);
  }
}

void main() {
  late FakeProjectRepository fakeProjects;
  late ProviderContainer container;

  setUp(() {
    fakeProjects = FakeProjectRepository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        projectRepositoryProvider.overrideWithValue(fakeProjects),
      ],
    );
    addTearDown(container.dispose);
    // Force the StreamProvider's subscription to start eagerly - reading
    // `.future` alone (with nothing else watching the base provider) can
    // otherwise leave it uninitialized.
    container.listen(authStateProvider, (_, __) {});
  });

  test('starts empty for a user with no projects', () async {
    await container.read(authStateProvider.future);
    final projects = await container.read(projectsProvider.future);
    expect(projects, isEmpty);
  });

  test('createProject adds and exposes the new project', () async {
    await container.read(authStateProvider.future);
    await container.read(projectsProvider.future);
    final ok = await container
        .read(projectsProvider.notifier)
        .createProject(name: 'CrossCare Pharmacy Marketing');

    expect(ok, isTrue);
    final projects = container.read(projectsProvider).value!;
    expect(projects, hasLength(1));
    expect(projects.first.name, 'CrossCare Pharmacy Marketing');
  });

  test('renameProject updates the name in place', () async {
    await container.read(authStateProvider.future);
    await container.read(projectsProvider.future);
    await container.read(projectsProvider.notifier).createProject(name: 'Old name');
    final id = container.read(projectsProvider).value!.first.id;

    await container.read(projectsProvider.notifier).renameProject(id, 'New name');

    final projects = container.read(projectsProvider).value!;
    expect(projects.first.name, 'New name');
  });

  test('deleteProject removes the project', () async {
    await container.read(authStateProvider.future);
    await container.read(projectsProvider.future);
    await container.read(projectsProvider.notifier).createProject(name: 'Temp project');
    final id = container.read(projectsProvider).value!.first.id;

    await container.read(projectsProvider.notifier).deleteProject(id);

    expect(container.read(projectsProvider).value, isEmpty);
  });
}
