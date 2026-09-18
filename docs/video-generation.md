# Video generation (Phase 4)

Phase 4 adds AI Video Generation on top of Phase 1/2/3, reusing the same
architecture as [image-generation.md](image-generation.md) and
[music-generation.md](music-generation.md) - read those first if you
haven't; this one only calls out what's different for video. The one
structural difference from every prior phase: **video generation is
genuinely asynchronous**, so this phase actually builds the job/poll
architecture that music-generation.md described but didn't need.

## What was reused vs. added

**Reused unchanged:** Supabase Auth/session, the `generations` table (same
columns, `generation_type = "video"`, no new table), `GenerationRepository`,
`GenerationOrchestrator` (extended additively - see below), `CreationType`/
`GenerationStatus` (added a `cancelled` status), the Create tab's category
picker, History and its filters (already iterated every `CreationType`, so
"History → Video" needed no new code), the credits summary, the shared
`GenerationDetailScreen` (extended, not duplicated), theme, navigation
shell, error handling, the private `app-storage` bucket, and Phase
2's `ReferenceImage` model / validator / `ReferenceImagePickerField` widget
(reused as-is for the optional reference image - the concept isn't
image-generation-specific).

**Added:**
- `supabase/functions/generate-video/` - starts a provider job and returns
  immediately (does not wait for the video).
- `supabase/functions/video-status/` - polled by the Flutter app while a
  video is processing; downloads and stores the finished video once the
  provider reports it's done.
- `lib/features/generation/services/edge_function_video_provider.dart` -
  the real `VideoAIProvider`, wired into `videoAIProviderProvider`.
- `lib/features/generation/services/video_status_checker.dart` - thin
  wrapper around calling `video-status`.
- `lib/features/generation/presentation/providers/video_polling_provider.dart`
  - `VideoPollingController`, a `Notifier.family` that owns the client-side
    polling timer for one generation.
- `lib/features/video_generation/` - the "AI Video Generator" screen and its
  settings model.
- `lib/core/widgets/video_player_widget.dart` - a reusable video player
  (`video_player` + `chewie`): play/pause/seek/duration/fullscreen/mute,
  loading/error states, preserves the video's real aspect ratio.
- `AIGenerationResult.isPending` (new, additive field, defaults to `false`)
  and a matching branch in `GenerationOrchestrator` - see "Async generation
  architecture" below.
- `GenerationDetailScreen` gained a video branch (`VideoPlayerWidget`
  instead of an image/audio player), a processing-state UI with a Cancel
  button that drives `VideoPollingController`, a cancelled-state message, a
  video-aware Download (`FilePicker.saveFile(type: FileType.video)`) and
  Share (video mime type/filename), and an Aspect ratio/Resolution/
  Duration/Style chip row read from `generations.metadata`.
- `Validators.videoPrompt` - unlike every other prompt validator, an *empty*
  prompt is valid as long as a reference image is attached (Image → Video
  mode).
- `GenerationRepository.deleteGenerationAndFiles` gained cleanup for
  `metadata.thumbnailStoragePath` - video is the first generation type with
  a separately-stored thumbnail object, so it needed its own cleanup entry
  alongside the existing `metadata.storagePath` one.

## Request flow (async, job-based)

```
VideoGeneratorScreen
  -> (optional) uploads the reference image, gets back a storage path
  -> CreateGenerationController.submit(type: video, options: {...settings})
  -> GenerationOrchestrator.generate()                     [Phase 1/2, extended]
       - creates the `generations` row (status: pending)
       - status: processing
       - calls EdgeFunctionVideoProvider.generate()
           -> supabase.functions.invoke('generate-video', body: {
                prompt, referenceImagePath, settings
              })
              == generate-video Edge Function ==
              - auth, validate, check credits, download reference image
              - provider.createJob() -> { jobId }
              - deducts credits
              - returns FAST: { success, status: 'processing', jobId, ... }
           <- AIGenerationResult(isPending: true, metadata: {jobId, ...})
       - orchestrator sees isPending=true -> leaves status as "processing",
         merges jobId/settings into metadata - does NOT mark completed
GenerationDetailScreen opens on the new (still-processing) generation
  -> starts VideoPollingController(generationId).start(jobId)
  -> every 4s, calls video-status Edge Function: { generationId, jobId }
       - re-verifies ownership (RLS) and that jobId matches the jobId
         recorded on that row (see "Provider job security" below)
       - provider.checkStatus(jobId) -> processing | completed | failed
       - on completed: downloads the video (+ thumbnail if any), uploads
         both to Storage, returns signed URLs - does NOT write to the
         `generations` table itself
  -> on completed/failed: VideoPollingController calls the existing
     GenerationRepository.updateGeneration() (RLS-protected, already
     tested) to persist the final result
  -> up to 40 attempts (~2.7 min); if still processing after that, the
     controller itself marks the generation failed ("taking longer than
     expected")
```

The Flutter HTTP request to `generate-video` is never held open for the
video's actual generation time - it returns as soon as the provider job is
created. All the waiting happens in short, cheap polls, exactly per the
brief's "do not keep the connection open" requirement.

## Async generation architecture

This is the one part of the architecture that prior phases built for but
never had to actually use (both the Phase 2 image provider and the Phase 3
music provider turned out to be synchronous). Video's connected provider,
Stability AI's Stable Video Diffusion, *is* genuinely job-based, so this
phase implements the real thing:

**`AIGenerationResult.isPending`** (new field, default `false`): when a
provider only started a job and hasn't produced a result yet, it returns
`isPending: true` with the job id and any other bookkeeping the poller will
need in `metadata`. `GenerationOrchestrator.generate()` checks this flag
right after calling the provider:
- `isPending == false` (every Phase 1-3 provider): existing behavior,
  unchanged - persist the result and mark `completed`.
- `isPending == true` (video): leave `status: processing` (already set
  before the provider call) and persist only `provider`/`model`/`metadata`
  (which includes the job id). A separate poller takes over from here - the
  orchestrator's job for this generation is done once the job exists.

**Two Edge Functions instead of one**, because starting a job and checking
its status are different operations with different security needs:
- `generate-video` - called once per generation. Authenticates, validates,
  checks credits and duplicate requests, starts the provider job, deducts
  credits, returns immediately.
- `video-status` - called repeatedly (polled) while `status == processing`.
  Cheap: re-authenticates, re-verifies ownership and job association, and
  only touches the provider/Storage when there's actually a status change
  to report.

**No webhook**, by design, for the reason music-generation.md already
documents for its own hypothetical webhook: implementing one without a
concrete provider payload to register against would mean inventing an
endpoint/payload shape, which the brief explicitly rules out. Client-side
polling (`VideoPollingController`, 4s interval) is what's real and tested
today. If a provider with documented webhook support is connected later,
the natural evolution is a `video-webhook` Edge Function that does what
`video-status` does today but is pushed to instead of polled - `index.ts`'s
request/response contract for `generate-video` would not need to change.

## Provider job security

A provider's job id is **never** treated as authorization by itself -
`video-status` requires the caller to also supply the `generationId`, and
then:
1. Authenticates the caller from their JWT (same as every other Edge
   Function in this project).
2. Reads that specific `generations` row through a client scoped to the
   caller's own JWT - Postgres RLS (`auth.uid() = user_id`) means this
   silently returns nothing if the caller doesn't own that row, which is
   treated as "not found."
3. Compares the `jobId` the caller supplied against the `jobId` recorded in
   `generations.metadata` when the job was created (`generate-video`
   writes it there). A mismatch is refused (`403 FORBIDDEN`) rather than
   checking an unrelated provider job - so a caller can't probe an
   arbitrary job id even if they own *some* generation row that happens to
   reference a different one.

Neither Edge Function writes to the `generations` table directly - the
single-writer principle from Phase 2 still holds. `video-status` returns
the resolved result to the (already-authenticated, already-verified)
Flutter client, which persists it through the existing, tested
`GenerationRepository.updateGeneration()`.

## Cancellation

Stable Video Diffusion's publicly documented API has no confirmed
cancel-job endpoint, so this phase does not invent one. What Cancel
actually does (`VideoPollingController.cancel()`):
1. Stops the local polling timer.
2. Marks the generation `cancelled` via the existing repository.

It does **not** guarantee the underlying provider job itself stops running
- there's no documented endpoint to ask it to. This is the honest
implementation of the brief's fallback instruction for providers that don't
support cancellation: *"stop client polling and keep server-side state
accurate"* - server-side state (the `generations` row) is accurate
(`cancelled`), even though the provider-side job isn't necessarily killed.
Navigating away from the detail screen instead calls `.stop()` (pause
without changing status) - the generation stays `processing` and resumes
being polled the next time its detail screen opens, since `start()` is a
no-op while already polling and safe to call on every screen build.

## The Edge Functions

```
supabase/functions/generate-video/
  index.ts             - auth, validation, credits, duplicate-request check, starts the job, returns fast
  types.ts              - shared request/response types, JobCreationResult/JobStatusResult
  providers/
    provider.ts          - VideoGenerationProvider interface: createJob() + checkStatus()
    mock_provider.ts      - development-mode provider (default)
    stability_provider.ts - real provider (Stability AI's Stable Video Diffusion)
    index.ts              - picks mock vs. stability from secrets

supabase/functions/video-status/
  index.ts             - polled by the client; verifies ownership + job association; resolves the job
  types.ts, providers/  - duplicated from generate-video (each Edge Function deploys independently)
```

Security model is identical to `generate-image`/`generate-music` (JWT-
derived identity, JWT-scoped client for Storage/`generations` reads,
service-role client scoped only to `subscriptions`/`credit_transactions` -
used only by `generate-video`, since `video-status` never touches credits -
`verify_jwt: true` at the platform level). Confirmed live: an
unauthenticated request to either function gets `401
UNAUTHORIZED_NO_AUTH_HEADER` from the gateway. Differences:
- **Duplicate-request window is 180s** (vs. 90s for music, 15s for images)
  - video jobs run the longest of any type so far.
- **Credit cost is a flat 5 credits** - deliberately the most expensive
  type so far per the brief, a placeholder until a real per-
  resolution/duration/provider cost model is needed.
- **`checkStatus` split out of `generate`**: every other provider interface
  in this project has one `generate()` method that returns the final
  result. `VideoGenerationProvider` has two - `createJob()` and
  `checkStatus()` - because starting and checking a job really are two
  different network calls against two different points in the provider's
  own API lifecycle, unlike image/music where "start" and "get result" are
  the same HTTP round trip.

## AI provider setup

| Secret | Values | Default |
|---|---|---|
| `VIDEO_GENERATION_PROVIDER` | `mock` \| `stability` | `mock` |
| `VIDEO_GENERATION_MODEL` | provider-specific model id | `stable-video-diffusion` |
| `VIDEO_GENERATION_API_KEY` | the provider's secret key (falls back to `STABILITY_API_KEY`) | - |

**Mock mode** (default, and what this project currently runs with - no key
configured): simulates a job by encoding a timestamp + aspect ratio into the
job id string itself (`mock:${timestamp}:${aspectRatio}`), since Edge
Functions have no persistent memory between invocations to track job state
any other way. After a simulated ~9s processing delay, `checkStatus`
fetches a small, long-standing public sample video
(Google's `ForBiggerBlazes.mp4`, used in their own ExoPlayer docs) plus a
placehold.co-generated thumbnail, and runs both through the full real
upload/DB/history/playback pipeline. No paid API is ever called.

**To enable real generation:**
```bash
supabase secrets set VIDEO_GENERATION_PROVIDER=stability
supabase secrets set VIDEO_GENERATION_API_KEY=sk-...
supabase functions deploy generate-video
supabase functions deploy video-status
```
As with images/music, setting the provider to `stability` without a key
fails loudly (`CONFIGURATION_ERROR`) instead of silently serving a mock
video.

### About the Stability AI implementation - please verify before production use

Implemented against Stability AI's publicly documented Stable Video
Diffusion endpoints (`POST
https://api.stability.ai/v2beta/image-to-video`, multipart/form-data to
start a job; `GET
https://api.stability.ai/v2beta/image-to-video/result/{id}` with `Accept:
video/*` - `202` while processing, `200` with raw video bytes once done) as
of the time this was written. **This has not been exercised against a real
API key** - no credentials were available. Before relying on it in
production:

1. Re-check https://platform.stability.ai/docs/api-reference against
   `supabase/functions/generate-video/providers/stability_provider.ts`.
2. Verify current commercial usage terms for generated video.
3. Known, deliberate gaps (mapped/handled, not silently pretended to work):
   - **Stable Video Diffusion is image-to-video only - it has no
     text-to-video capability.** `createJob()` throws a clear
     `MISSING_REFERENCE_IMAGE` error (surfaced to the user as a friendly
     message) if no reference image was provided, rather than silently
     ignoring the prompt or pretending text-only generation works. The
     Video Generator screen's prompt is optional specifically so
     Image → Video requests without a prompt are still valid client-side -
     but a prompt-only request will fail server-side against this provider
     until a text-capable video provider is connected.
   - Stable Video Diffusion has **no aspect ratio / resolution / duration /
     style / fps parameters** - it takes an image and a `motion_bucket_id`.
     `motion` (low/medium/high) maps to `motion_bucket_id` (80/127/180);
     every other setting is stored in `generations.metadata` for display
     and regeneration, but is not sent to the provider.
   - No confirmed cancel-job endpoint - see "Cancellation" above.

## Settings → provider mapping

| Setting | Stable Video Diffusion mapping |
|---|---|
| Motion (low/medium/high) | `motion_bucket_id` = 80 / 127 / 180 |
| Aspect ratio / Resolution / Duration / Style / Fps | stored in `generations.metadata` only - no native parameters on this provider |
| Prompt | not sent - Stable Video Diffusion is image-conditioned only, no text prompt input |

## Storage

Generated video is stored in the existing private `app-storage` bucket at
`{user_id}/generations/{request_id}/result.{mp4\|webm}` - extension chosen
from the provider's actual `Content-Type` (never assumed), same convention
as images/audio. A thumbnail, when the provider or mock supplies one, is
stored **as a separate object** at
`{user_id}/generations/{request_id}/thumbnail.png`. The Flutter app only
ever receives short-lived (1 hour) signed URLs for both. Both paths are
kept in `generations.metadata` (`storagePath`, `thumbnailStoragePath`) so
`deleteGenerationAndFiles()` can remove both objects on delete - video is
the first generation type where the primary result and its thumbnail live
at two different Storage paths that both need cleaning up, so this method
gained a second cleanup entry for `thumbnailStoragePath` this phase.

## Video player

`lib/core/widgets/video_player_widget.dart` wraps `video_player` +
`chewie` (both newly added dependencies): play/pause, seek, progress,
duration, fullscreen, mute/unmute, a loading state while the network video
initializes, and an error state if it fails - Chewie's own Material
controls provide all of this, so no custom playback UI was hand-rolled.
`aspectRatio` is read from the initialized `VideoPlayerController` itself
(not assumed from the generation's `aspectRatio` setting), so portrait,
landscape, and square video all render without stretching.

## How to test

```bash
flutter analyze
flutter test
```

To exercise the real pipeline end to end in mock mode (no key needed): sign
in, go to Create → Video, enter a prompt (or attach a reference image),
tap Generate Video. The detail screen shows a "Creating your video..."
state with a Cancel button, polls automatically, and after ~9 simulated
seconds shows a short public sample video with working playback, tagged
`mock`/`mock-video-v1`, and shows up in History → filter: Video.

**Known testing gap:** live authenticated round-trip testing of
`generate-video`/`video-status` (the same way `generate-image` was
verified live in Phase 2) could not be completed in this session - only
unauthenticated `401` gateway checks were verified live for both functions
(confirming `verify_jwt: true` is active). The Dart-side
`EdgeFunctionVideoProvider`, `VideoStatusChecker`, and
`VideoPollingController` (including its start/completed/failed/cancel/
no-double-poll behavior) are covered by unit tests instead, using a fake
Edge Function invoker rather than a live network call. There is currently
no automated test runner for the Deno Edge Function code itself, matching
Phases 2 and 3.

## Deployment

```bash
supabase link --project-ref <your-project-ref>
supabase functions deploy generate-video
supabase functions deploy video-status
```
(For this project, both are already deployed - see the README's Supabase
configuration table.)
