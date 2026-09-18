import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports whether the device currently has network connectivity.
///
/// This is a best-effort link-layer check (Wi-Fi/mobile data present), not a
/// guarantee of internet reachability - good enough to stop the user from
/// starting an AI generation while offline and to show an offline banner.
class NetworkService {
  NetworkService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return _hasConnection(results);
  }

  Stream<bool> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map(_hasConnection);

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
