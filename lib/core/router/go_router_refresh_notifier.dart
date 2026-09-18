import 'package:flutter/foundation.dart';

/// Bridges Riverpod's `ref.listen` to a [Listenable] so [GoRouter]'s
/// `refreshListenable` re-evaluates `redirect` whenever auth state changes.
///
/// Deliberately driven by an explicit [notify] call from `app_router.dart`'s
/// `ref.listen(authStateProvider, ...)`, rather than independently
/// re-wrapping `authRepository.authStateChanges` in its own stream
/// subscription. Two separate subscriptions to the same underlying auth
/// stream previously caused a real startup race: `redirect` reads
/// `ref.read(authStateProvider)`, but the *trigger* to re-run `redirect`
/// came from a second, independently-constructed stream instance. Nothing
/// guaranteed that second stream's first event would arrive at or after the
/// point `authStateProvider` itself had already updated - if it arrived
/// first, `redirect` re-ran, read a still-`AsyncLoading` `authStateProvider`,
/// deferred back to `/splash`, and (with no sign-in/out ever happening) no
/// further event ever arrived to trigger a second re-check. The app was
/// stuck on the splash screen indefinitely. Listening to the exact same
/// provider instance that `redirect` reads removes that race entirely: the
/// trigger and the data can never disagree about whether auth state has
/// resolved.
class GoRouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
