import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/funnel_lead_model.dart';

/// Data access for `funnel_leads`. See docs/funnel-generation.md: Phase 5
/// only supports the funnel *owner's* own authenticated session submitting
/// (e.g. to test the Lead Form component against their own funnel) - there
/// is no public/unauthenticated visitor pathway yet, since that requires a
/// future "publish" phase's dedicated, rate-limited Edge Function.
abstract class FunnelLeadsRepository {
  Future<Result<FunnelLeadModel>> submitLead({
    required String funnelId,
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? message,
  });
  Future<Result<List<FunnelLeadModel>>> getLeads(String funnelId);
  Future<Result<void>> deleteLead(String id);
}

class SupabaseFunnelLeadsRepository implements FunnelLeadsRepository {
  SupabaseFunnelLeadsRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'funnel_leads';

  @override
  Future<Result<FunnelLeadModel>> submitLead({
    required String funnelId,
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? message,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .insert({
            'funnel_id': funnelId,
            'user_id': userId,
            if (name != null && name.isNotEmpty) 'name': name,
            if (email != null && email.isNotEmpty) 'email': email,
            if (phone != null && phone.isNotEmpty) 'phone': phone,
            if (message != null && message.isNotEmpty) 'message': message,
          })
          .select()
          .single();
      return Result.success(FunnelLeadModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<List<FunnelLeadModel>>> getLeads(String funnelId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('funnel_id', funnelId)
          .order('created_at', ascending: false);
      return Result.success((rows as List).map((r) => FunnelLeadModel.fromJson(r)).toList());
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> deleteLead(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
