# Cross-Platform Architecture

CreateAI Studio is one Flutter codebase, one Supabase backend, and one set of feature
modules. This document records what "cross-platform" actually means for this app, what
had to change to get there, and what is deliberately still platform-specific and why.

## Supported platforms

**Primary** (the app itself): Android, iOS, Windows.
**Target/future-compatible** (scaffolded and dependency-compatible, not yet build-verified
in this environment): macOS, Linux.
**Public web**: the published-funnel viewer only (`/f/:slug`), not the private app. See
"Public funnels vs. the app" below.

Platform folders present in the repo today: `android/`, `windows/`. `ios/`, `macos/`,
`linux/`, `web/` have not been scaffolded yet - see "Known limitations" for why, and
`docs/PLATFORM_SUPPORT_MATRIX.md` for exactly what is and isn't validated per platform.

## What's shared (everything, by default)

Business logic, repositories, providers, models, Supabase integration, auth,
credits/usage, the funnel system, project/history management, and validation are *all*
plain Dart in `lib/`, with zero platform branching. This was true before this work and
remains true after it - a repo-wide search for `Platform.isX`/`dart:io`/`kIsWeb` before
this change found **zero** conditional platform logic anywhere in `lib/`. The only
platform-specific decisions introduced by this work are the three described below, and
each lives behind one interface/registration point, not scattered `if (Platform.isX)`
checks through feature code.

## Platform-specific pieces (only three exist)

### 1. Media playback (Windows/Linux)

`just_audio` and `video_player` (used via `chewie`) have no official Windows/Linux
implementation - only Android, iOS, macOS, and Web are covered by the official plugins.
Rather than replace either package (which would mean rewriting `AudioPlayerController`
and `VideoPlayerWidget`, the two single-point wrappers every screen already goes through),
two packages are registered in `lib/main.dart` that implement the *existing*
`just_audio_platform_interface`/`video_player_platform_interface` for Windows/Linux only:

- `just_audio_media_kit` (backed by `media_kit`) for audio.
- `fvp` (backed by `libmdk`) for video, registered with
  `platforms: ['windows', 'linux']` so it never touches Android/iOS/macOS/Web, where the
  official plugins keep running unmodified.

Application code (`lib/core/audio/audio_player_controller.dart`,
`lib/core/widgets/video_player_widget.dart`, `lib/core/widgets/audio_player_widget.dart`)
needed **zero changes** - they call `just_audio`/`video_player`'s own public API, which is
identical regardless of which platform implementation answers it.

### 2. Image downloads (desktop)

`gal` (used to save a generated image to the system photo gallery) only supports
Android/iOS - there is no macOS/Windows/Linux implementation. Video and music downloads
already went through `FilePicker.saveFile` (a genuine save-as dialog, already
cross-platform), so only the image path needed a fix.
`lib/core/services/media_save_service.dart` is the one interface: `saveImageBytes()`
calls `Gal.putImageBytes` on Android/iOS and falls back to `FilePicker.saveFile` on
Windows/macOS/Linux, so `generation_detail_screen.dart` has one call site with no platform
checks of its own.

### 3. Responsive navigation shell

`lib/core/design/breakpoints.dart` defines Material 3's window-size-class breakpoints
(`compact` < 600dp, `medium` 600-839dp, `expanded` ≥ 840dp) as the single source of truth
for "is this window phone-sized or desktop-sized." `AppShell`
(`lib/core/widgets/app_shell.dart`) reads that breakpoint - not the OS - and shows:

- **compact**: the original bottom `NavigationBar` (unchanged from before this work).
- **medium**: a collapsed `NavigationRail` (icons + labels below each icon).
- **expanded**: an extended `NavigationRail` (icons + inline labels, more like a sidebar).

This is a window-size decision, not a platform decision: a narrow desktop window gets the
bottom bar, and a large Android tablet gets the rail. No screen or feature needed to
change - `AppShell` wraps every route via the existing `StatefulShellRoute`.

## Authentication

Supabase Auth (email/password) works identically on every platform - `supabase_flutter`
is pure Dart plus platform-agnostic HTTP/WebSocket, with no native code of its own. No
auth logic changed as part of this work.

### The Splash → Login hang (investigated, not re-introduced)

A previously-fixed race (commit `beeee47`, prior to this work) is worth restating here
since cross-platform work touches app startup: `GoRouter`'s `redirect` reads
`authStateProvider` directly, and is *triggered* to re-run via
`GoRouterRefreshNotifier.notify()`, called from the exact same
`ref.listen(authStateProvider, ...)` subscription in `app_router.dart` - not a second,
independently-subscribed stream. That was the actual root cause: two separate
subscriptions to the same underlying auth stream could disagree about *when* auth state
had resolved, and if the trigger fired before the data was ready, the redirect bounced
back to `/splash` with nothing left to trigger a second check. This fix is
platform-independent (it's pure Dart/Riverpod, no native code), so it applies identically
on Windows/iOS/macOS/Linux without any further changes. Verified still in place; no
changes made to auth/router logic in this pass beyond what Phase 7 already added (the
narrow `isPublicFunnelRoute` redirect bypass).

## Supabase (one backend, every platform)

Every platform talks to the same Supabase project - Auth, Postgres, RLS, Storage, and
Edge Functions are unchanged by this work. No platform gets its own database, its own
auth flow, or elevated credentials. The client only ever holds the anon/publishable key;
AI provider keys and the service-role key live exclusively in Edge Functions, unchanged.

## AI generation

Image/Music/Video/Funnel generation all call the same Edge Functions over plain HTTPS
(`http`, `supabase_flutter`), which is platform-agnostic by construction - there was
nothing to change here for cross-platform support. Only *playback* of the results
(music/video) needed the platform-specific backend described above; *generating* them
never did.

## File handling

`dart:io.File` is used directly in a handful of files (`reference_image.dart`,
`file_upload_service.dart`, and three picker-field widgets) since every currently
supported/target platform (Android, iOS, Windows, macOS, Linux) has a real filesystem via
`dart:io`. This is safe as long as the private app itself never targets Flutter Web - the
brief is explicit that it shouldn't, and it doesn't. If that ever changes, these files
would need to move to an `XFile`/bytes-based abstraction, since `dart:io` doesn't exist on
web; that migration was scoped but deliberately not done here since it isn't needed yet.

## Public funnels vs. the app

The Phase 7 public funnel viewer (`/f/:slug`, `PublicFunnelViewScreen`,
`PublicLeadFormWidget`) already reads and writes exclusively through the sanitized
`get_public_funnel`/`submit_funnel_lead` RPCs and contains no `dart:io` usage - it was
already, incidentally, Web-compatible code before this work. It remains a route inside the
same app, not a separate deployment; if/when a standalone web build of just that route is
built, it is a separate, explicitly scoped follow-up (per the brief: "do not add Flutter
Web merely to preview the private app").

## Sharing and downloads

`share_plus` already supports every target platform natively (Android/iOS share sheet,
desktop clipboard/OS share where available, with Copy Link always offered as a fallback in
`PublishStatusCard` since Phase 7) - no changes were needed here. Downloads are covered
above (`MediaSaveService` for images; `FilePicker.saveFile` already handled video/music).

## Build commands

| Command | Status this session |
|---|---|
| `flutter analyze` | ✅ clean |
| `flutter test` | ✅ 212/212 passing |
| `flutter build apk --debug` | ✅ (Android licenses accepted this session) |
| `flutter build windows` | Requires Windows Developer Mode (symlink support) - see matrix |
| `flutter build ios --no-codesign` | Not run - no macOS/Xcode host in this environment |
| `flutter build macos` | Not run - no macOS host in this environment |
| `flutter build linux` | Not run - no Linux host/toolchain in this environment; `linux/` platform folder not yet scaffolded |

## Known limitations

- **No `ios/`, `macos/`, `linux/`, `web/` platform folders yet.** `windows/` was added and
  is dependency-compatible; the same `flutter create --platforms=...` step for the others
  is mechanical but requires a host capable of validating the result (macOS for
  iOS/macOS, a Linux toolchain for Linux) - see the matrix for exactly what's unverified.
- **Secure storage**: Supabase session persistence uses its default (SharedPreferences-
  backed) storage on every platform - there is no `flutter_secure_storage`-backed adapter
  configured. This predates this work and applies equally to Android/iOS today; it is not
  a new cross-platform gap, just an existing one worth tracking.
- **Notifications**: no notification package exists in the project. If generation jobs
  ever need to notify the user directly (as opposed to the in-app history/polling that
  already exists), that's new work, not a compatibility fix.
- **Payments**: Phase 6's credit/subscription system remains provider-neutral by
  construction (verified: zero references to Google Play Billing, Apple IAP, or any
  payment SDK anywhere in `lib/`). No real payment integration was added or is required by
  this pass.
- **Window management**: no `window_manager`/`bitsdojo_window`-style customization
  (minimum size, custom title bar) was added - Windows/macOS/Linux use the default OS
  window chrome from the Flutter desktop template as-is.
