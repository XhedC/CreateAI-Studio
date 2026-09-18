/// Central place for product-identity constants.
///
/// Change [appName] here (and the Android label in
/// android/app/src/main/AndroidManifest.xml) to rename the product without
/// touching any other file.
class AppConstants {
  const AppConstants._();

  static const String appName = 'CreateAI Studio';
  static const String appTagline = 'Your AI-powered creative studio';

  /// The single Storage bucket the app uses. Every object is namespaced
  /// under `{user_id}/...` (see core/utils/storage_paths.dart) and access is
  /// enforced by the storage RLS policies in supabase/migrations - see
  /// docs/database.md for the folder layout.
  static const String storageBucket = 'app-storage';

  // Pagination / list defaults.
  static const int defaultPageSize = 20;

  // Local persistence keys.
  static const String prefThemeMode = 'pref_theme_mode';
  static const String prefLocale = 'pref_locale';
}
