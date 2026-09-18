import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/funnel_model.dart';
import '../models/funnel_schema.dart';
import '../models/public_funnel_view.dart';

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

  /// Publishes (or republishes) a funnel via the `publish-funnel` Edge
  /// Function - see docs/PHASE_7_PUBLISHING.md "Publishing lifecycle".
  /// Reuses the funnel's existing `public_slug` if it already has one
  /// (republish), otherwise generates and reserves a new collision-safe
  /// slug (first publish). Returns the freshly-updated row.
  Future<Result<FunnelModel>> publishFunnel(String id);

  /// Unpublishes a funnel: the public page immediately stops resolving,
  /// the draft is untouched, and `public_slug` is deliberately left
  /// in place so a later republish reuses the same URL. Uses the owner's
  /// own RLS-scoped update - no elevated privilege is needed for this.
  Future<Result<FunnelModel>> unpublishFunnel(String id);

  /// Fetches the sanitized public view of a published funnel by its
  /// public slug - callable by a fully anonymous visitor (just the anon
  /// key, no session). Returns `null` for a draft, unpublished, or
  /// nonexistent slug - these are intentionally indistinguishable to a
  /// public caller (see docs/PHASE_7_PUBLISHING.md "Public error pages").
  Future<Result<PublicFunnelView?>> getPublicFunnel(String slug);
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

  @override
  Future<Result<FunnelModel>> publishFunnel(String id) async {
    try {
      final response = await _client.functions.invoke(
        'publish-funnel',
        body: {'funnelId': id},
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        return Result.failure(PublishException(
          message: _publishErrorMessage(data),
          code: data is Map ? data['code'] as String? : null,
        ));
      }
      // The function only returns the slug/version, not the full row.
      return getFunnel(id);
    } on FunctionException catch (e) {
      return Result.failure(PublishException(
        message: _publishErrorMessage(e.details),
        code: e.details is Map ? (e.details as Map)['code'] as String? : null,
        cause: e,
      ));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  String _publishErrorMessage(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong while publishing your funnel. Please try again.';
  }

  @override
  Future<Result<FunnelModel>> unpublishFunnel(String id) async {
    try {
      final row = await _client
          .from(_table)
          .update({
            'published': false,
            'unpublished_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();
      return Result.success(FunnelModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<PublicFunnelView?>> getPublicFunnel(String slug) async {
    try {
      final result = await _client.rpc('get_public_funnel', params: {'p_slug': slug});
      if (result == null) return const Result.success(null);
      return Result.success(PublicFunnelView.fromJson((result as Map).cast<String, dynamic>()));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
