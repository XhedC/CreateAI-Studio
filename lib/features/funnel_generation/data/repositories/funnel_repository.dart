import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/funnel_model.dart';
import '../models/funnel_schema.dart';

/// Data access for the `funnels` table. Deliberately thin - cross-table
/// orchestration (e.g. "duplicate a funnel" needs a new `generations` row
/// too) lives in `funnel_providers.dart`, not here, matching how
/// `GenerationRepository` stays a plain CRUD layer and
/// `GenerationOrchestrator` owns the multi-step workflow.
///
/// There is deliberately no `deleteFunnel` here - a funnel's `generation_id`
/// foreign key is `on delete cascade`, so deleting the linked `generations`
/// row (via the existing, already-tested `GenerationRepository`) removes
/// the funnel automatically. See docs/funnel-generation.md.
abstract class FunnelRepository {
  Future<Result<List<FunnelModel>>> getFunnels(String userId, {String? projectId});
  Future<Result<FunnelModel>> getFunnel(String id);
  Future<Result<FunnelModel?>> getFunnelByGenerationId(String generationId);
  Future<Result<FunnelModel>> insertFunnel({
    required String userId,
    String? projectId,
    required String generationId,
    required String name,
    String? description,
    required String funnelType,
    required FunnelSchema content,
  });
  Future<Result<FunnelModel>> updateFunnel(
    String id, {
    String? name,
    FunnelSchema? content,
    String? status,
  });
}

class SupabaseFunnelRepository implements FunnelRepository {
  SupabaseFunnelRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'funnels';

  @override
  Future<Result<List<FunnelModel>>> getFunnels(String userId, {String? projectId}) async {
    try {
      var query = _client.from(_table).select().eq('user_id', userId);
      if (projectId != null) {
        query = query.eq('project_id', projectId);
      }
      final rows = await query.order('updated_at', ascending: false);
      return Result.success((rows as List).map((r) => FunnelModel.fromJson(r)).toList());
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<FunnelModel>> getFunnel(String id) async {
    try {
      final row = await _client.from(_table).select().eq('id', id).single();
      return Result.success(FunnelModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<FunnelModel?>> getFunnelByGenerationId(String generationId) async {
    try {
      final row =
          await _client.from(_table).select().eq('generation_id', generationId).maybeSingle();
      return Result.success(row == null ? null : FunnelModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<FunnelModel>> insertFunnel({
    required String userId,
    String? projectId,
    required String generationId,
    required String name,
    String? description,
    required String funnelType,
    required FunnelSchema content,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .insert({
            'user_id': userId,
            if (projectId != null) 'project_id': projectId,
            'generation_id': generationId,
            'name': name,
            if (description != null) 'description': description,
            'funnel_type': funnelType,
            'schema_version': content.version,
            'content': content.toJson(),
          })
          .select()
          .single();
      return Result.success(FunnelModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<FunnelModel>> updateFunnel(
    String id, {
    String? name,
    FunnelSchema? content,
    String? status,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .update({
            if (name != null) 'name': name,
            if (content != null) 'content': content.toJson(),
            if (content != null) 'schema_version': content.version,
            if (status != null) 'status': status,
          })
          .eq('id', id)
          .select()
          .single();
      return Result.success(FunnelModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
