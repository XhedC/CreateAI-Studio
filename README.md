# CreateAI Studio

An AI Creative Studio mobile app: users describe what they want in natural
language (and optionally attach files) and the app routes the request to the
right AI generation pipeline - text, image, music, video, or landing-page
funnels. **Phase 1** built the foundation: auth, Supabase integration,
database, dashboard, projects/history, settings, and the reusable
AI-generation architecture, with every generation type mocked. **Phase 2**
connected **AI Image Generation** to a real backend, **Phase 3** connected
**AI Music Generation** the same way, **Phase 4** connected **AI Video
Generation**, **Phase 5** connected an **AI Funnel/Landing Page
Generator**, and **Phase 6** built the **Credits, Usage & Subscription
foundation** - each generation type's Edge Function is a provider-agnostic
vendor abstraction, all currently running in safe development (mock) mode
until a real AI provider key is configured - see
[docs/image-generation.md](docs/image-generation.md),
[docs/music-generation.md](docs/music-generation.md),
[docs/video-generation.md](docs/video-generation.md),
[docs/funnel-generation.md](docs/funnel-generation.md), and
[docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md](docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md).
Video is the first type that's genuinely asynchronous (job created →
polled → completed) rather than one synchronous request/response; a
funnel's result is a structured, versioned JSON document (rendered as real
Flutter widgets, never raw HTML) rather than a single media file. Every
generation now reserves credits atomically before calling its AI provider
and refunds them on definitive failure - see Phase 6 below. Text remains
mocked pending a later phase.

> "CreateAI Studio" is a working name. Rename it in one place:
> [`lib/core/config/app_constants.dart`](lib/core/config/app_constants.dart)
> (`AppConstants.appName`) plus the Android label in
> [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml).

## Technology stack

- **Frontend**: Flutter (Dart 3.7+), Material 3, [Riverpod](https://riverpod.dev) for state/DI, [go_router](https://pub.dev/packages/go_router) for navigation.
- **Backend**: [Supabase](https://supabase.com) - Postgres, Auth, Storage, Row Level Security, and five Edge Functions (`generate-image`, `generate-music`, `generate-video`, `video-status`, `generate-funnel`) that hold AI provider secrets server-side - see [docs/image-generation.md](docs/image-generation.md), [docs/music-generation.md](docs/music-generation.md), [docs/video-generation.md](docs/video-generation.md), and [docs/funnel-generation.md](docs/funnel-generation.md).
- **Audio**: [just_audio](https://pub.dev/packages/just_audio) powers a single app-wide player shared by the Music Detail screen and the mini-player docked above the bottom navigation.
- **Video**: [video_player](https://pub.dev/packages/video_player) + [chewie](https://pub.dev/packages/chewie) power a reusable video player with fullscreen/mute/seek controls.
- **Funnels**: a structured JSON schema (versioned, validated, safely corrected) rendered entirely as Flutter widgets - no HTML/WebView anywhere in the app.
- **Architecture**: feature-based (`lib/features/<feature>/{data,services,presentation}`), repository pattern, a provider-agnostic `AIProvider` abstraction (see [docs/ai-integration.md](docs/ai-integration.md)).
- **Target**: Android first (package id placeholder `com.createaistudio.app`); the architecture has no iOS-specific assumptions, so `flutter create --platforms ios .` can add it later without restructuring.

## Project structure

```
lib/
  core/            # config, theme, routing, errors, shared widgets, DI providers
  features/
    auth/          # register, login, logout, forgot password, session state
    home/          # dashboard
    create/        # (folded into generation/) creation-type picker + prompt UI
    generation/    # AIProvider abstraction, mock + real (image/music/video/funnel) providers, orchestrator, Create + detail screens
    image_generation/ # AI Image Generator screen, settings/reference-image models (Phase 2)
    music_generation/  # AI Music Generator screen, settings model (Phase 3)
    video_generation/  # AI Video Generator screen, settings model (Phase 4)
    funnel_generation/ # AI Funnel Builder, schema/validator, editor, preview, lead form (Phase 5)
    history/       # generation history, filter, search
    projects/      # project CRUD
    profile/       # profile screen
    settings/      # theme, notifications, language
    credits/       # credits/subscription: balance, plans, costs, ledger, usage dashboard (Phase 6)
    notifications/ # in-app notifications list (placeholder)
  core/audio/      # AudioPlayerController - single app-wide just_audio player (Phase 3)
  core/widgets/video_player_widget.dart # reusable video_player + chewie player (Phase 4)
supabase/
  migrations/      # SQL: tables, indexes, RLS, storage policies, triggers
  functions/
    generate-image/ # Edge Function: auth, credits, AI provider call, Storage upload (Phase 2)
    generate-music/  # Edge Function: same pattern, for audio (Phase 3)
    generate-video/  # Edge Function: starts an async job, returns immediately (Phase 4)
    video-status/    # Edge Function: polled by the client, resolves the job (Phase 4)
    generate-funnel/ # Edge Function: validates AI output into a FunnelSchema, stores it (Phase 5)
docs/              # architecture, database, AI-integration, image/music/video/funnel-generation deep dives
env/               # local dart-define config (gitignored except *.example)
```

## Installation

### Prerequisites

- Flutter SDK 3.29+ (Dart 3.7+) - `flutter doctor` should be clean for Android.
- Android Studio / Android SDK + an emulator or device.
- A [Supabase](https://supabase.com) project (free tier is enough).

### 1. Get dependencies

```bash
flutter pub get
```

### 2. Supabase setup

**A Supabase project has already been provisioned for this Phase 1 build**
(see "Supabase configuration" below for its URL/key). To use your own project
instead:

1. Create a project at [supabase.com](https://supabase.com).
2. Run every file in [`supabase/migrations/`](supabase/migrations/) against it, in filename order - via the Supabase SQL editor, or the CLI:
   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```
3. Copy your project's URL and anon/publishable key from Project Settings → API.

### 3. Environment configuration

Secrets are **never** hard-coded or bundled as an asset. They're injected at
build/run time via `--dart-define-from-file`:

```bash
cp env/dev.json.example env/dev.json
# edit env/dev.json with your SUPABASE_URL and SUPABASE_ANON_KEY
```

`env/*.json` is gitignored - only `env/dev.json.example` is tracked.

### 4. Run locally

```bash
flutter run --dart-define-from-file=env/dev.json
```

### 5. Build for Android

```bash
flutter build apk --release --dart-define-from-file=env/dev.json
```

The release build currently signs with the debug keystore (see the `TODO` in
`android/app/build.gradle.kts`) purely so `flutter build apk --release` works
out of the box - replace it with a real signing config before a Play Store
upload.

## Supabase configuration required

| Setting | Value |
|---|---|
| Project URL | set via `SUPABASE_URL` in `env/dev.json` |
| Anon/publishable key | set via `SUPABASE_ANON_KEY` in `env/dev.json` |
| Database | see [docs/database.md](docs/database.md) for the full schema |
| Storage | one private bucket, `app-storage`, created by `supabase/migrations/20250101040000_storage.sql` |
| Auth | Email/password sign-up must be enabled (default). Email confirmation is on by default - disable it in Auth settings for faster local testing if you want. |
| Edge Functions | `generate-image`, `generate-music`, `generate-video`, `video-status`, `generate-funnel` - all deployed with `verify_jwt: true`, all run in mock mode by default - see below to enable a real AI provider. |

This app's own Supabase project was provisioned automatically for this build:
- URL: `https://gnhxqthfskshxrnwwugb.supabase.co`
- All migrations in `supabase/migrations/` have already been applied to it (tables, indexes, RLS, storage bucket + policies, triggers, including `funnels`/`funnel_leads`).
- The `generate-image`, `generate-music`, `generate-video`, `video-status`, and `generate-funnel` Edge Functions are already deployed to it and reachable.
- `env/dev.json` already points at it, so `flutter run --dart-define-from-file=env/dev.json` works immediately.
- Treat it as a personal/dev project: rotate the key or create your own project before shipping to production.

### AI providers

No AI provider keys are configured yet, so all Edge Functions run in
**mock mode**: they produce a labelled placeholder image / a short
synthesized melody / a short sample video / a fully-structured funnel
document through the full real pipeline (Storage upload, database record,
History, playback) - no paid API is called. To enable real generation:
```bash
# Images (OpenAI)
supabase secrets set AI_IMAGE_PROVIDER=openai
supabase secrets set AI_IMAGE_API_KEY=sk-...
supabase functions deploy generate-image

# Music (Stability AI)
supabase secrets set MUSIC_GENERATION_PROVIDER=stability
supabase secrets set MUSIC_GENERATION_API_KEY=sk-...
supabase functions deploy generate-music

# Video (Stability AI - image-to-video only)
supabase secrets set VIDEO_GENERATION_PROVIDER=stability
supabase secrets set VIDEO_GENERATION_API_KEY=sk-...
supabase functions deploy generate-video
supabase functions deploy video-status

# Funnels (OpenAI, JSON-mode chat completions)
supabase secrets set FUNNEL_GENERATION_PROVIDER=openai
supabase secrets set FUNNEL_GENERATION_API_KEY=sk-...
supabase functions deploy generate-funnel
```
Full details, settings-to-provider mappings, and known limitations to verify
before production: [docs/image-generation.md](docs/image-generation.md),
[docs/music-generation.md](docs/music-generation.md),
[docs/video-generation.md](docs/video-generation.md), and
[docs/funnel-generation.md](docs/funnel-generation.md).

## Running locally

```bash
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

## Running tests

```bash
flutter analyze
flutter test
```

## What's working

**Phase 1:**
- Registration, login, logout, forgot password, session persistence (Supabase Auth).
- Profile (name, email, avatar placeholder), Settings (theme mode, notifications toggle, language field).
- Dashboard: greeting, credit balance card, quick-create tiles, recent creations, recent projects.
- Projects: create, rename, delete, open; a project shows its own generations.
- Light/dark/system theme, persisted locally.
- Centralized error handling (friendly messages only; technical detail is logged, never shown), offline detection with a banner, loading/empty states everywhere data is fetched.
- Row Level Security on every table; a private Storage bucket namespaced per user.
- Create screen: Chat still runs the **mocked** pipeline (pending → processing → completed) end to end.

**Phase 2 (AI Image Generation):**
- Dedicated "AI Image Generator" screen (Create → Image): prompt with example helper text, optional camera/gallery reference image (format/size validated), expandable Image Settings (aspect ratio, quality, style, number of images 1-4), low-credits warning.
- Real backend pipeline: Supabase Edge Function `generate-image` authenticates the caller from their JWT (never a client-supplied id), checks credits, calls the configured AI provider (mock by default, OpenAI when configured), uploads the result to the private `app-storage` bucket, and returns a signed URL - the AI provider secret never exists in the Flutter app.
- History → filter: Image shows a real thumbnail per card; the detail screen has working **Download** (saves to the device gallery), **Share** (native share sheet), **Regenerate** (creates a new generation, keeps the original), and **Delete** (removes the database record and its Storage files).
- Duplicate-request protection and a credits check before every generation.

**Phase 3 (AI Music Generation):**
- Dedicated "AI Music Generator" screen (Create → Music): prompt, optional lyrics with a "Generate Lyrics Automatically" toggle (reuses Phase 1's text-generation service), expandable Music Settings (genre, mood, vocal type, language, duration, tempo).
- Real backend pipeline: Supabase Edge Function `generate-music` - same security model as `generate-image` - calls the configured AI provider (mock by default, Stability AI's Stable Audio when configured), uploads audio to `app-storage`, returns a signed URL. Music costs 3 credits per generation (vs. 1-4 for images), and its duplicate-request window is wider (90s vs. 15s) since real generation runs longer.
- A single app-wide audio player (`just_audio`): full player (play/pause/seek/duration/position) on the Music Detail screen, plus a mini-player docked above the bottom navigation that keeps playing while you navigate.
- History → filter: Music shows generated tracks; the detail screen's Download/Share/Regenerate/Delete all work for audio too (Download uses a file-save dialog rather than the photo gallery, since audio isn't a photo).

**Phase 4 (AI Video Generation):**
- Dedicated "AI Video Generator" screen (Create → Video): prompt (optional if a reference image is attached - Image → Video mode), optional reference image (reuses Phase 2's picker/validator), expandable Video Settings (aspect ratio, resolution, duration, motion, style, fps).
- **Genuinely asynchronous pipeline** - the first generation type where the Flutter app does not hold one request open for the whole generation. `generate-video` starts a provider job and returns immediately; `video-status` is polled every 4s by `VideoPollingController` until the job resolves, at which point it downloads the video into `app-storage` and the client persists the final result through the existing repository. Provider job ids are never trusted as authorization by themselves - `video-status` re-verifies row ownership and that the supplied job id matches the one recorded when the job was created.
- Video costs 5 credits per generation (the most expensive type so far, per the brief), with a wider 180s duplicate-request window since video jobs run longest.
- A reusable video player (`video_player` + `chewie`): play/pause/seek/duration/fullscreen/mute, correct aspect ratio for portrait/landscape/square video.
- Processing state shows a "Creating your video..." indicator with a Cancel button; cancelling stops polling and marks the generation cancelled (Stable Video Diffusion has no confirmed cancel-job endpoint, so this is honestly client-side-only - see [docs/video-generation.md](docs/video-generation.md)).
- History → filter: Video shows generated clips; the detail screen's Download/Share/Regenerate/Delete all work for video too (Download uses a file-save dialog, matching music's pattern; Delete also cleans up the video's separately-stored thumbnail object).

**Phase 5 (AI Funnel/Landing Page Generator):**
- Dedicated "AI Funnel Builder" screen (Create → Funnel): prompt, business fields (name, type, product, target audience, offer, CTA), funnel type (15 types + custom), main goal, optional Logo and Product/Reference image uploads.
- Real backend pipeline: Supabase Edge Function `generate-funnel` calls the configured AI provider (mock by default, OpenAI JSON-mode chat completions when configured), validates/safely-corrects the response into a versioned `FunnelSchema`, and stores it in a new `funnels` table linked to its `generations` row - never raw, unvalidated JSON, and never rendered as HTML.
- A structured `FunnelRenderer` draws every section (hero, benefits, features, services, pricing, testimonials, FAQ, contact, lead form, appointment CTA, final CTA, footer, ...) as real Flutter widgets.
- A basic Funnel Editor: rename, edit section text, hide/show/delete/add sections, reorder via drag-and-drop or Move Up/Down, Save.
- A responsive Funnel Preview (Mobile/Tablet/Desktop) rendering the exact same schema through the exact same renderer.
- A reusable Lead Form component with validation and success/error states, backed by a new `funnel_leads` table (strict RLS; no third-party lead delivery).
- History → filter: Funnel shows generated funnels; View/Edit/Duplicate/Delete all work (Duplicate creates a new funnel+generation without touching the original; Delete reuses the existing generation-delete path via a cascading foreign key).
- Funnels cost 4 credits per generation, and reuse the existing Project system (a funnel's `project_id` is copied from its generation, same as every other type).

**Phase 6 (Credits, Usage & Subscription Foundation):**
- DB-driven `plans` (Free/Pro/Business) and `credit_costs` tables - no plan limit or generation cost is hardcoded in Flutter or in an Edge Function; every generator screen shows the live cost next to its Generate button.
- Credit charging moved to an atomic, race-safe `reserve_credits` RPC called *before* the AI provider, replacing each Edge Function's old post-hoc "deduct credits" check; refunded via `refund_generation_credits` on any definitive failure (provider error, invalid response, storage/DB failure). Video's async job now gets refunded on a provider-reported failure too - a real pre-existing gap this phase closed.
- Every credit-moving operation (charge, refund, monthly grant) is idempotent via a dedicated `idempotency_keys` table - retries and concurrent duplicate requests can never double-charge or double-refund.
- New Plan/Subscription, Usage Dashboard, and paginated Credit History screens. Selecting a paid plan shows "payment integration coming soon" - **no real payment processing exists yet**, by design.
- A `SubscriptionProvider` abstract interface for a future payment integration (Stripe, Play Billing, ...) - unimplemented, no credentials, mirrors the existing `AIProvider` pattern.
- See [docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md](docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md) for the full design, race-safety, and idempotency writeup.

## What's not yet implemented

- Verified, production-ready AI vendor integrations - the OpenAI (images/funnels) and Stability AI (music/video) implementations are all written against publicly documented endpoints but have not been exercised against a real key; see "known gaps" in [docs/image-generation.md](docs/image-generation.md) / [docs/music-generation.md](docs/music-generation.md) / [docs/video-generation.md](docs/video-generation.md) / [docs/funnel-generation.md](docs/funnel-generation.md) before enabling any of them in production.
- Real credit *purchases* or subscription upgrades - the billing foundation (balances, ledger, atomic/idempotent charge-and-refund, DB-driven plans/costs) is implemented and enforced server-side; no payment provider is integrated, so a plan can be viewed but not actually purchased yet.
- Push notifications (in-app notifications list exists; nothing populates it yet).
- Avatar upload flow in Profile (storage path/bucket support this; the screen only shows a placeholder today).
- A provider webhook for video completion - not needed today since the connected provider (Stability's Stable Video Diffusion) has no documented webhook to register against; client-side polling is what's real and tested. See "Async generation architecture" in [docs/video-generation.md](docs/video-generation.md).
- Guaranteed provider-side job cancellation for video - Cancel stops client polling and marks the generation cancelled server-side, but cannot confirm the provider itself stops the job (no documented endpoint for that).
- The future Image + Music → Video combined workflow mentioned in the Phase 4 brief - the architecture doesn't block it, but it isn't implemented since no connected provider supports it today.
- Item-level editing for a funnel section's list content (e.g. individual benefits/testimonials/FAQ entries) - only top-level text fields (headline, title, description, ...) are editable in this version; see [docs/funnel-generation.md](docs/funnel-generation.md).
- Public funnel publishing, custom domains, HTML/ZIP export, and embed codes - explicitly out of scope for Phase 5; the funnel schema is already structured so a future export/publish pipeline can consume it directly.
- Anonymous (unauthenticated) lead submission - `funnel_leads` RLS only allows the funnel owner's own session to insert today; a future "publish" phase needs a dedicated, rate-limited Edge Function for real visitor submissions.
- iOS project files (Android-only, per the brief).

## Recommended next phase

Real payment-provider integration (Stripe, Google Play Billing, ...) against
the `SubscriptionProvider` interface Phase 6 already defined, then Play
Store packaging (real signing config, app icon, privacy policy, permissions
review). Public funnel publishing (with custom domains/hosting) is a
natural follow-on once payments exist to gate it.

## Documentation

- [docs/architecture.md](docs/architecture.md) - folder structure, state management, navigation, error handling conventions.
- [docs/database.md](docs/database.md) - full schema, RLS policy rationale, storage layout.
- [docs/ai-integration.md](docs/ai-integration.md) - the `AIProvider` abstraction and how to plug in a real provider.
- [docs/image-generation.md](docs/image-generation.md) - the Phase 2 Edge Function, AI provider setup, mock mode, and how to switch providers.
- [docs/music-generation.md](docs/music-generation.md) - the Phase 3 Edge Function, audio player architecture, async-generation design, and how to switch providers.
- [docs/video-generation.md](docs/video-generation.md) - the Phase 4 Edge Functions, the genuinely-async job/poll architecture, provider job security, cancellation, and how to switch providers.
- [docs/funnel-generation.md](docs/funnel-generation.md) - the Phase 5 funnel schema, JSON validation/safe-correction, the Edge Function, the structured renderer, the editor/preview, leads, and future publishing architecture.
- [docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md](docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md) - the Phase 6 credit/subscription schema, atomic race-safe charging, idempotency, Edge Function billing integration, and the future payment-provider architecture.
#   C r e a t e A I - S t u d i o  
 