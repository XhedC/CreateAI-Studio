import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_constants.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/generation_file_model.dart';
import '../models/generation_model.dart';

abstract class GenerationRepository {
  Future<Result<List<GenerationModel>>> getGenerations(
    String userId, {
    String? generationType,
    String? projectId,
    String? searchQuery,
  });
  Future<Result<GenerationModel>> getGeneration(String id);
  Future<Result<GenerationModel>> createGeneration({
    required String userId,
    String? projectId,
    required String generationType,
    required String prompt,
  });
  Future<Result<GenerationModel>> updateGeneration(
    String id, {
    String? status,
    String? provider,
    String? model,
    String? resultText,
    String? resultUrl,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
    String? errorMessage,
    DateTime? completedAt,
  });
  Future<Result<void>> deleteGeneration(String id);

  /// Deletes the generation row AND any Storage objects it owns (its main
  /// result, tracked in `metadata.storagePath`, plus every attached
  /// `generation_files` row). Storage cleanup is best-effort - a failed
  /// object removal never blocks deleting the database record, since RLS
  /// already guarantees those objects are unreachable/orphaned afterwards.
  Future<Result<void>> deleteGenerationAndFiles(GenerationModel generation);

  Future<Result<GenerationFileModel>> attachFile({
    required String generationId,
    required String userId,
    required String fileName,
    required String fileType,
    required String mimeType,
    required String storagePath,
    String? fileUrl,
    int? fileSize,
  });
  Future<Result<List<GenerationFileModel>>> getFiles(String generationId);
}

class SupabaseGenerationRepository implements GenerationRepository {
  SupabaseGenerationRepository(this._client);

  final SupabaseClient _client;
  static const _generationsTable = 'generations';
  static const _filesTable = 'generation_files';

  @override
  Future<Result<List<GenerationModel>>> getGenerations(
    String userId, {
    String? generationType,
    String? projectId,
    String? searchQuery,
  }) async {
    try {
      var query = _client.from(_generationsTable).select().eq('user_id', userId);
      if (generationType != null) {
        query = query.eq('generation_type', generationType);
      }
      if (projectId != null) {
        query = query.eq('project_id', projectId);
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        query = query.ilike('prompt', '%${searchQuery.trim()}%');
      }
      final rows = await query.order('created_at', ascending: false);
      return Result.success(
        (rows as List).map((r) => GenerationModel.fromJson(r)).toList(),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<GenerationModel>> getGeneration(String id) async {
    try {
      final row = await _client
          .from(_generationsTable)
          .select()
          .eq('id', id)
          .single();
      return Result.success(GenerationModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<GenerationModel>> createGeneration({
    required String userId,
    String? projectId,
    required String generationType,
    required String prompt,
  }) async {
    try {
      final row = await _client
          .from(_generationsTable)
          .insert({
            'user_id': userId,
            if (projectId != null) 'project_id': projectId,
            'generation_type': generationType,
            'prompt': prompt,
            'status': 'pending',
          })
          .select()
          .single();
      return Result.success(GenerationModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<GenerationModel>> updateGeneration(
    String id, {
    String? status,
    String? provider,
    String? model,
    String? resultText,
    String? resultUrl,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
    String? errorMessage,
    DateTime? completedAt,
  }) async {
    try {
      final row = await _client
          .from(_generationsTable)
          .update({
            if (status != null) 'status': status,
            if (provider != null) 'provider': provider,
            if (model != null) 'model': model,
            if (resultText != null) 'result_text': resultText,
            if (resultUrl != null) 'result_url': resultUrl,
            if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
            if (metadata != null) 'metadata': metadata,
            if (errorMessage != null) 'error_message': errorMessage,
            if (completedAt != null) 'completed_at': completedAt.toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();
      return Result.success(GenerationModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> deleteGeneration(String id) async {
    try {
      await _client.from(_generationsTable).delete().eq('id', id);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> deleteGenerationAndFiles(GenerationModel generation) async {
    try {
      final storagePaths = <String>[];

      final mainPath = generation.metadata['storagePath'] as String?;
      if (mainPath != null && mainPath.isNotEmpty) {
        storagePaths.add(mainPath);
      }

      // Video generations store their thumbnail as a separate Storage object
      // (see video-status Edge Function), so it needs its own cleanup entry.
      final thumbnailPath = generation.metadata['thumbnailStoragePath'] as String?;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        storagePaths.add(thumbnailPath);
      }

      final filesResult = await getFiles(generation.id);
      filesResult.when(
        success: (files) =>
            storagePaths.addAll(files.map((f) => f.storagePath)),
        failure: (_) {},
      );

      if (storagePaths.isNotEmpty) {
        try {
          await _client.storage
              .from(AppConstants.storageBucket)
              .remove(storagePaths);
        } catch (_) {
          // Best-effort: proceed to delete the row even if some/all objects
          // were already gone or couldn't be removed.
        }
      }

      await _client.from(_generationsTable).delete().eq('id', generation.id);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<GenerationFileModel>> attachFile({
    required String generationId,
    required String userId,
    required String fileName,
    required String fileType,
    required String mimeType,
    required String storagePath,
    String? fileUrl,
    int? fileSize,
  }) async {
    try {
      final row = await _client
          .from(_filesTable)
          .insert({
            'generation_id': generationId,
            'user_id': userId,
            'file_name': fileName,
            'file_type': fileType,
            'mime_type': mimeType,
            'storage_path': storagePath,
            if (fileUrl != null) 'file_url': fileUrl,
            if (fileSize != null) 'file_size': fileSize,
          })
          .select()
          .single();
      return Result.success(GenerationFileModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<List<GenerationFileModel>>> getFiles(String generationId) async {
    try {
      final rows = await _client
          .from(_filesTable)
          .select()
          .eq('generation_id', generationId)
          .order('created_at');
      return Result.success(
        (rows as List).map((r) => GenerationFileModel.fromJson(r)).toList(),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
