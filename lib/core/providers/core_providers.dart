import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../network/network_service.dart';

/// Overridden in `main.dart` with the resolved [SharedPreferences] instance
/// before the app is run, so every other provider can read it synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart',
  );
});

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseConfig.client;
});

final networkServiceProvider = Provider<NetworkService>((ref) {
  return NetworkService();
});

/// Live connectivity stream, seeded with the current status.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final network = ref.watch(networkServiceProvider);
  yield await network.isConnected;
  yield* network.onConnectivityChanged;
});
