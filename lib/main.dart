import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/providers/core_providers.dart';
import 'core/utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows/Linux have no official just_audio/video_player implementation -
  // both packages register themselves only for those two platforms, so
  // Android/iOS/macOS/Web keep using the official plugins untouched. See
  // docs/CROSS_PLATFORM_ARCHITECTURE.md "Media playback".
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: true);
    fvp.registerWith(options: {
      'platforms': ['windows', 'linux'],
    });
  }

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
