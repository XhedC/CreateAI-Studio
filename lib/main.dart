import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/providers/core_providers.dart';
import 'core/utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  try {
    await SupabaseConfig.initialize();
  } catch (e, st) {
    // Surfaced again in the UI via env_config.isConfigured checks; logging
    // here helps diagnose a missing --dart-define-from-file during `flutter run`.
    AppLogger.error('Supabase initialization failed', error: e, stackTrace: st);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CreateAiStudioApp(),
    ),
  );
}
