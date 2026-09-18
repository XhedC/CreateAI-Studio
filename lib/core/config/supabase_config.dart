import 'package:supabase_flutter/supabase_flutter.dart';

import 'env_config.dart';

/// Thin wrapper around Supabase initialization so the rest of the app never
/// touches [Supabase.initialize] directly.
class SupabaseConfig {
  const SupabaseConfig._();

  static Future<void> initialize() async {
    if (!EnvConfig.isConfigured) {
      throw StateError(
        'Supabase is not configured. Run the app with '
        '--dart-define-from-file=env/dev.json (see README.md).',
      );
    }

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      publishableKey: EnvConfig.supabaseAnonKey,
      debug: !EnvConfig.isProduction,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
