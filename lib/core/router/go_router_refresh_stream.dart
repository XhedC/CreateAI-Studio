import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a [Stream] (Riverpod's auth state stream) to a [Listenable] so
/// [GoRouter]'s `refreshListenable` re-evaluates `redirect` whenever auth
/// state changes, without polling.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
