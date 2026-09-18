/// Build-time environment configuration.
///
/// Values are injected at build/run time via `--dart-define-from-file`
/// (preferred) or individual `--dart-define=KEY=VALUE` flags. Nothing here is
/// hard-coded and nothing secret is bundled into the compiled app: the
/// Supabase anon key is safe to ship in a client per Supabase's security
/// model (real access control is enforced by Row Level Security), while any
/// private AI provider key stays server-side in Supabase Edge Functions and
/// is never read by this app.
///
/// See README.md "Environment configuration" for setup instructions.
class EnvConfig {
  const EnvConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const bool isProduction = bool.fromEnvironment(
    'PRODUCTION',
    defaultValue: false,
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
