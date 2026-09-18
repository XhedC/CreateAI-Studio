# Architecture

## Folder structure

```
lib/
  main.dart              # bootstraps SharedPreferences + Supabase, runs the app
  app.dart               # MaterialApp.router, theme wiring
  core/
    config/              # env vars (dart-define), Supabase client init, app-wide constants
    constants/           # CreationType and GenerationStatus enums (shared taxonomy)
    errors/              # AppException hierarchy + ErrorHandler
    network/             # connectivity check
    providers/           # cross-cutting Riverpod providers (Supabase client, SharedPreferences, connectivity)
    router/              # go_router config, route paths, auth redirect
    theme/                # Material 3 light/dark theme, theme-mode persistence
    utils/                # Result<T>, validators, date formatting, storage path builder, logger
    widgets/              # reusable UI: AppButton, AppTextField, cards, empty/error/loading states, bottom nav, shell, audio player, mini-player
    audio/                # AudioPlayerController - the single app-wide just_audio player (Phase 3)
  features/
    <feature>/
      data/
        models/           # plain Dart model classes with fromJson/toInsertJson
        repositories/     # abstract interface + Supabase implementation, returns Result<T>
      services/            # generation/ only: AIProvider abstraction + mock/real implementations + orchestrator
      presentation/
        providers/         # Riverpod providers/controllers wiring repositories to the UI
        screens/            # full-page widgets
        widgets/            # feature-local widgets
```

`image_generation/` (Phase 2) follows the same shape for everything
image-specific - `ImageGenerationSettings`, `ReferenceImage`, the reference
image validator, and the dedicated "AI Image Generator" screen - while
reusing `generation/`'s `GenerationModel`, `GenerationRepository`,
`GenerationOrchestrator`, and `CreationType` rather than duplicating them.
The real `ImageAIProvider` implementation
(`edge_function_image_provider.dart`) lives in `generation/services/`
alongside the mock providers, since it's an `AIProvider` implementation
like they are, not image-generation-specific business logic - see
[ai-integration.md](ai-integration.md) and
[image-generation.md](image-generation.md).

`music_generation/` (Phase 3) follows the identical pattern -
`MusicGenerationSettings` plus the "AI Music Generator" screen - reusing
everything in `generation/` the same way `image_generation/` does. Its real
`MusicAIProvider` implementation (`edge_function_music_provider.dart`) lives
in `generation/services/` for the same reason. Audio *playback*
(`AudioPlayerController`, `AudioPlayerWidget`, `MiniPlayer`) lives in
`core/`, not the music feature, because `AppShell` - a core widget - renders
the mini-player and core must not depend on a feature; see
[music-generation.md](music-generation.md).

`video_generation/` (Phase 4) follows the same pattern again -
`VideoGenerationSettings` plus the "AI Video Generator" screen - and reuses
Phase 2's `ReferenceImage`/`ReferenceImagePickerField` directly (a
cross-feature import from `image_generation/`, justified because the
reference-image concept isn't image-specific). Its real `VideoAIProvider`
implementation (`edge_function_video_provider.dart`) lives in
`generation/services/` alongside the others. Unlike image/music, video
generation is genuinely asynchronous: `AIGenerationResult` gained an
`isPending` field, `GenerationOrchestrator` gained a branch that leaves a
pending generation's status as `processing` instead of `completed`, and a
new `VideoPollingController` (`generation/presentation/providers/`) owns
the client-side polling loop that eventually resolves it. Video *playback*
(`VideoPlayerWidget`) lives in `core/widgets/`, not the video feature, for
the same reason `AudioPlayerWidget` does - it's a generic, reusable player,
not video-generation-specific logic. See
[video-generation.md](video-generation.md).

`funnel_generation/` (Phase 5) is the largest feature yet, since a
funnel's "result" is a whole structured document rather than one media
file: `FunnelSchema`/`FunnelSection`/`FunnelTheme`/`FunnelSeo` models, a
`FunnelSchemaValidator` (the Dart mirror of the Edge Function's own
validator - see below), `FunnelRepository`/`FunnelLeadsRepository`, the
"AI Funnel Builder" generator screen, the structured `FunnelEditorScreen` +
`FunnelEditorController`, the responsive `FunnelPreviewScreen`, the
`FunnelRenderer` (maps each section type to real Flutter widgets - never
HTML), and the reusable `LeadFormWidget`. Its real `FunnelAIProvider`
implementation (`edge_function_funnel_provider.dart`) lives in
`generation/services/` for the same reason as the others. `GenerationOrchestrator`
gained one small additive field, `AIGenerationRequest.generationId`, since
`generate-funnel` (unlike every other Edge Function) needs to link the
funnel it stores back to the generation that requested it - see
[funnel-generation.md](funnel-generation.md) for why. `GenerationDetailScreen`
(in `generation/`, the shared screen every type extends) imports directly
from `funnel_generation/` for its funnel summary card - the one deliberate
exception to the "shared screens don't import leaf features" direction
video/image follow, made because a funnel's content genuinely lives in its
own table/feature rather than being renderable generically.

Every feature follows the same shape, so a new feature (e.g. adding a
sixth creation type) is a copy of this structure, not a new pattern to
invent.

## State management & dependency injection

[Riverpod](https://riverpod.dev) (v3, no code generation) is the single state
management + DI mechanism:

- **`Provider<T>`** exposes a service/repository built from other providers
  (e.g. `projectRepositoryProvider` builds a `SupabaseProjectRepository` from
  `supabaseClientProvider`). Swapping an implementation - a fake in tests, or
  a real AI provider later - means overriding one `Provider`, nothing else.
- **`StreamProvider<AppUser?>`** (`authStateProvider`) is the single source of
  truth for "is someone logged in" - the router, guards, and every screen
  that needs the current user read from it.
- **`FutureProvider`/`FutureProvider.family`** load read-only, request-scoped
  data (a generation's detail, a project's generations).
- **`AsyncNotifier<T>`** drives anything with a mutation + loading/error state
  a screen needs to react to (`AuthController`, `CreateGenerationController`,
  `ProjectsNotifier`). Screens call a method on `.notifier` and `ref.watch`
  the `AsyncValue` for loading/error UI.

Repositories never throw raw exceptions to callers - every method returns
`Result<T>` (`Success<T>` or `Failure<T>` wrapping an `AppException`), so a
caller can't forget to handle failure. `ErrorHandler.handle()` is the only
place raw Supabase/dart:io exceptions get translated into a friendly
`AppException`.

## Navigation

`go_router` with a `StatefulShellRoute.indexedStack` for the 5 bottom-nav
tabs (Home, Create, History, Projects, Profile) - each tab keeps its own
navigation stack and scroll position when switching. Detail screens
(generation detail, project detail) and utility screens (Settings,
Notifications) are top-level routes pushed on top of the shell, not nested
inside a tab, so the back button behaves predictably everywhere.

`redirect` in `app_router.dart` is the single auth guard: unauthenticated
users are bounced to `/login`, authenticated users can't land back on
`/login`/`/register`/`/splash`. It re-runs automatically on every auth state
change via a small `GoRouterRefreshStream` bridging Riverpod's auth stream to
`GoRouter`'s `Listenable`-based `refreshListenable`.

## Error handling & offline behavior

- `AppException` subtypes (`AuthException`, `ValidationException`,
  `NetworkException`, `DatabaseException`, `StorageException`,
  `GenerationException`, `UnknownException`) carry only a user-safe
  `message`; the original error/stack trace is attached for logging only.
- `ErrorHandler.handle()` maps Supabase's `AuthApiException`,
  `PostgrestException`, and storage exceptions to the right `AppException`,
  with friendlier copy for common auth failures (wrong password, duplicate
  email, weak password, rate limiting).
- `NetworkService` wraps `connectivity_plus`; `isOnlineProvider` drives the
  `OfflineBanner` shown in the app shell, and `GenerationOrchestrator` refuses
  to start a generation while offline instead of letting it fail later.
- Every list/detail screen has three states covered by dedicated widgets:
  `LoadingWidget`, `AppErrorWidget` (with retry), `EmptyState`.

## Reusable UI components

`lib/core/widgets/`: `AppButton` (loading-aware), `AppTextField`
(password-visibility toggle built in), `LoadingWidget`, `AppErrorWidget`,
`EmptyState`, `ProjectCard`, `GenerationCard`, `CreditCard`, `FeatureCard`,
`AppBottomNavigation`, `AppShell`, `OfflineBanner`. Screens compose these
instead of hand-rolling layout, so a visual change (e.g. card corner radius)
is a one-file edit.

## Adding a new feature/screen

1. Create `lib/features/<name>/{data,presentation}` following an existing
   feature's shape.
2. Add a repository interface + Supabase implementation returning `Result<T>`.
3. Add Riverpod providers in `presentation/providers/`.
4. Add the screen(s) in `presentation/screens/`, using the shared widgets.
5. Register the route in `core/router/app_router.dart` (+ `route_paths.dart`).
6. If it needs new tables, add a new timestamped file under
   `supabase/migrations/` - never edit an already-applied migration.
7. If it needs a paid AI provider or any other secret, that secret goes into
   a new `supabase/functions/<name>/` Edge Function's environment (`supabase
   secrets set ...`), never into the Flutter app - see
   [image-generation.md](image-generation.md) for a full worked example
   (auth via forwarded JWT, service-role client scoped to only the tables
   that need it, provider abstraction on the Deno side too).
