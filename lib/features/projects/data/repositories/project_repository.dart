import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/project_model.dart';

abstract class ProjectRepository {
  Future<Result<List<ProjectModel>>> getProjects(String userId);
  Future<Result<ProjectModel>> getProject(String projectId);
  Future<Result<ProjectModel>> createProject({
    required String userId,
    required String name,
    String? description,
    String projectType = 'general',
  });
  Future<Result<ProjectModel>> renameProject(String projectId, String newName);
  Future<Result<void>> deleteProject(String projectId);
}

class SupabaseProjectRepository implements ProjectRepository {
  SupabaseProjectRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'projects';

  @override
  Future<Result<List<ProjectModel>>> getProjects(String userId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);
      return Result.success(
        (rows as List).map((r) => ProjectModel.fromJson(r)).toList(),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<ProjectModel>> getProject(String projectId) async {
    try {
      final row =
          await _client.from(_table).select().eq('id', projectId).single();
      return Result.success(ProjectModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<ProjectModel>> createProject({
    required String userId,
    required String name,
    String? description,
    String projectType = 'general',
  }) async {
    try {
      final row = await _client
          .from(_table)
          .insert({
            'user_id': userId,
            'name': name,
            if (description != null && description.isNotEmpty)
              'description': description,
            'project_type': projectType,
          })
          .select()
          .single();
      return Result.success(ProjectModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<ProjectModel>> renameProject(
    String projectId,
    String newName,
  ) async {
    try {
      final row = await _client
          .from(_table)
          .update({'name': newName})
          .eq('id', projectId)
          .select()
          .single();
      return Result.success(ProjectModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> deleteProject(String projectId) async {
    try {
      await _client.from(_table).delete().eq('id', projectId);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
