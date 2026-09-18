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

  /// The production domain published funnels are served from - e.g.
  /// `https://your-domain.example`. Deliberately never hard-coded and
  /// never defaulted to a fake-looking production URL: an unconfigured
  /// build falls back to a clearly-relative path (`/f/<slug>`) so nothing
  /// displayed ever LOOKS like a working link when it isn't one. See
  /// docs/PHASE_7_PUBLISHING.md "Environment / secrets" - this is a
  /// display/share-link value only, never used for API calls, so it is
  /// safe to ship in a client build like every other value in this file.
  static const String publicAppUrl = String.fromEnvironment(
    'PUBLIC_APP_URL',
    defaultValue: '',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// The full public URL for a published funnel's slug - `publicAppUrl`
  /// concatenated with `/f/<slug>`, or a bare relative path if
  /// `PUBLIC_APP_URL` was never configured for this build.
  static String publicFunnelUrl(String slug) {
    final base = publicAppUrl.replaceAll(RegExp(r'/+$'), '');
    return base.isEmpty ? '/f/$slug' : '$base/f/$slug';
  }
}
