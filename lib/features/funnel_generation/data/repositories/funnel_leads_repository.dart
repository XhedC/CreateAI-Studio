import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/funnel_lead_model.dart';

/// Data access for `funnel_leads`.
///
/// [submitLead] is the funnel *owner's* own authenticated-session path
/// (e.g. to test the Lead Form component against their own funnel) -
/// unchanged since Phase 5.
///
/// [submitPublicLead] is the Phase 7 addition: a fully anonymous visitor
/// (no session at all) submitting a published funnel's lead form. It goes
/// through the `submit_funnel_lead` SECURITY DEFINER RPC rather than a
/// direct table insert, since `funnel_leads` deliberately has zero
/// anonymous-insert RLS policy - see
/// supabase/migrations/20250101080000_funnel_publishing.sql and
/// docs/PHASE_7_PUBLISHING.md "Public lead form".
abstract class FunnelLeadsRepository {
  Future<Result<FunnelLeadModel>> submitLead({
    required String funnelId,
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? message,
  });
  Future<Result<void>> submitPublicLead({
    required String slug,
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
  Future<Result<void>> submitPublicLead({
    required String slug,
    String? name,
    String? email,
    String? phone,
    String? message,
  }) async {
    try {
      final result = await _client.rpc('submit_funnel_lead', params: {
        'p_slug': slug,
        'p_name': name,
        'p_email': email,
        'p_phone': phone,
        'p_message': message,
      });
      final map = (result as Map).cast<String, dynamic>();
      if (map['success'] != true) {
        return Result.failure(ValidationException(
          map['error'] as String? ?? 'This submission could not be processed.',
        ));
      }
      return const Result.success(null);
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
