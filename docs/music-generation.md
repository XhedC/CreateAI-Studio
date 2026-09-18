# Music generation (Phase 3)

Phase 3 adds AI Music Generation on top of Phase 1/2, reusing the same
architecture as [image-generation.md](image-generation.md) - read that
document first if you haven't; this one only calls out what's different for
audio.

## What was reused vs. added

**Reused unchanged:** Supabase Auth/session, the `generations` table (same
columns, `generation_type = "music"`), `GenerationRepository`,
`GenerationOrchestrator`, `CreationType`/`GenerationStatus`, the Create tab's
category picker, History and its filters (already iterated every
`CreationType`, so "History → Music" needed no new code), the credits
summary, `GenerationCard`/`GenerationDetailScreen` (extended, not
duplicated), theme, navigation shell, error handling, the private
`app-storage` bucket, and Phase 1's mocked text-generation service (reused
for "Generate Lyrics Automatically" - see below).

**Added:**
- `supabase/functions/generate-music/` - the Edge Function.
- `lib/features/generation/services/edge_function_music_provider.dart` -
  the real `MusicAIProvider` implementation wired into
  `musicAIProviderProvider`, replacing the Phase 1 mock for Music only.
- `lib/features/music_generation/` - the "AI Music Generator" screen and its
  settings model.
- `lib/core/audio/audio_player_controller.dart` +
  `lib/core/widgets/audio_player_widget.dart` +
  `lib/core/widgets/mini_player.dart` - a single app-wide audio player
  (`just_audio`) shared by the Music Detail screen's full player and the
  mini-player docked above the bottom navigation bar, so playback survives
  navigating between screens. Placed in `core/` (not the music feature)
  because `AppShell`, a core widget, needs to render the mini-player without
  core depending on a feature.
- `GenerationDetailScreen` gained an audio branch (artwork placeholder +
  `AudioPlayerWidget` instead of an image), a music-aware Download (saves
  via `FilePicker.saveFile` - a "Save As" dialog, not the photo gallery -
  since audio isn't a photo) and Share (audio mime type/filename), and a
  small Genre/Mood/Duration chip row read from `generations.metadata`.
- Two validators added to the existing `Validators` class: `musicPrompt`,
  `lyrics` (both optional-friendly; lyrics has no "required" check).

## Request flow

```
MusicGeneratorScreen
  -> if "Generate Lyrics Automatically" is on and lyrics is empty:
       ref.read(textGenerationServiceProvider).generate(...)   [Phase 1, reused, mocked]
       -> lyrics text is filled into the Lyrics field before continuing
  -> CreateGenerationController.submit(type: music, options: {...settings, lyrics})
  -> GenerationOrchestrator.generate()                          [Phase 1/2, unchanged]
       - creates the `generations` row (status: pending)
       - status: processing
       - calls EdgeFunctionMusicProvider.generate()
           -> supabase.functions.invoke('generate-music', body: {
                prompt, lyrics, settings
              })
              == Supabase Edge Function ==
           <- { success, audio: {...}, provider, model, metadata }
       - persists result_url/metadata, status: completed (or failed)
GenerationDetailScreen reads the row back - artwork + AudioPlayerWidget,
Download/Share/Regenerate/Delete
```

Same single-writer design as Phase 2: the Edge Function never touches the
`generations` table itself; the already-tested orchestrator owns that.

## The Edge Function (`supabase/functions/generate-music`)

```
index.ts             - request handling, auth, validation, credits, storage upload
types.ts              - shared request/response types
providers/
  provider.ts          - MusicGenerationProvider interface
  mock_provider.ts      - development-mode provider (default)
  stability_provider.ts - real provider (Stability AI's Stable Audio API)
  index.ts              - picks mock vs. stability from secrets
```

Security model is identical to `generate-image` (see
[image-generation.md](image-generation.md)'s security section - JWT-derived
identity, JWT-scoped client for Storage/`generations` reads, service-role
client scoped only to `subscriptions`/`credit_transactions`, `verify_jwt:
true` at the platform level - confirmed live: an unauthenticated request to
`generate-music` gets `401 UNAUTHORIZED_NO_AUTH_HEADER` from the gateway).
Differences:
- **Duplicate-request window is 90s** (vs. 15s for images), because a real
  music provider call can run tens of seconds - a shorter window would
  false-positive against a single legitimate in-flight generation.
- **Credit cost is a flat 3 credits** (vs. 1-4 for images, scaled by
  `numberOfImages`) - music is deliberately made to cost more, per the
  brief, as a placeholder until a real per-provider/duration cost model is
  needed. Both live in the Edge Function only; the client never decides its
  own price.

## Async generation architecture

The brief asks for the architecture to support `pending -> processing ->
completed/failed` and, for a job-based provider, a poll or webhook pattern
instead of holding one long mobile HTTP request open.

**What's actually true for the provider wired up here:** Stability AI's
Stable Audio `text-to-audio` endpoint is **synchronous** - one HTTP request
returns the final audio directly, no job ID or polling involved. So
`generate-music` calls it exactly like `generate-image` calls OpenAI: one
request in, final bytes out, within the same Edge Function invocation.

**What the architecture is ready for, but doesn't need to use here:**
`MusicGenerationProvider.generate()` (see `providers/provider.ts`) is
documented as returning the *final* result from the caller's perspective. A
future provider whose real API *is* job-based (submit -> poll -> download)
would implement that polling **inside** its own `generate()` method, bounded
by a timeout, throwing `ProviderError(..., 'TIMEOUT')` if it doesn't finish
in time - the Edge Function's `index.ts` and the Flutter side would not
change at all. If a provider's jobs can run long enough that even internal
polling isn't practical within one Edge Function invocation (Supabase Edge
Functions have an execution time limit), the correct evolution is:
1. `generate-music` creates the job and returns immediately with
   `{ status: 'processing', jobId }` (no audio yet).
2. A **webhook** Edge Function (e.g. `music-webhook`), registered with the
   provider, receives the completion callback, downloads the result,
   uploads it to Storage, and updates the `generations` row directly
   (the one case where an Edge Function *would* need to touch that table,
   since nothing else is left holding the connection to do it).
3. Flutter polls `generationByIdProvider` (already built, already used by
   every detail screen) on a short interval, or the app subscribes to a
   Supabase Realtime channel on the row, until `status` leaves `processing`.

This isn't implemented because there's no real job-based provider connected
to build and test it against - implementing the webhook receiver without a
provider to register it with would mean inventing its payload shape, which
is exactly what "do not invent API endpoints or request parameters" rules
out. The synchronous path above is what's real and tested today.

## AI provider setup

| Secret | Values | Default |
|---|---|---|
| `MUSIC_GENERATION_PROVIDER` | `mock` \| `stability` | `mock` |
| `MUSIC_GENERATION_MODEL` | provider-specific model id | `stable-audio-2` |
| `MUSIC_GENERATION_API_KEY` | the provider's secret key (falls back to `STABILITY_API_KEY`) | - |

**Mock mode** (default, and what this project currently runs with - no key
configured): synthesizes a short melody **in-process** (a sine-wave WAV
built from scratch in the Edge Function, no external network call at all)
and runs it through the full upload/DB/history/playback pipeline. No paid
API is ever called.

**To enable real generation:**
```bash
supabase secrets set MUSIC_GENERATION_PROVIDER=stability
supabase secrets set MUSIC_GENERATION_API_KEY=sk-...
supabase functions deploy generate-music
```
As with images, setting the provider to `stability` without a key fails
loudly (`CONFIGURATION_ERROR`) instead of silently serving mock audio.

### About the Stability AI implementation - please verify before production use

Implemented against Stability AI's publicly documented Stable Audio
text-to-audio endpoint (`POST
https://api.stability.ai/v2beta/audio/stable-audio-2/text-to-audio`,
multipart/form-data, `Accept: audio/*` to get raw bytes back) as of the time
this was written. **This has not been exercised against a real API key** -
no credentials were available. Before relying on it in production:

1. Re-check https://platform.stability.ai/docs/api-reference against
   `supabase/functions/generate-music/providers/stability_provider.ts`.
2. Verify current commercial usage terms for generated audio.
3. Known, deliberate gaps (mapped/handled, not silently pretended to work):
   - Stable Audio has **no discrete genre/mood/vocal-type/tempo/language
     parameters** - it's a free-text-prompt model. All of those settings
     are folded into the prompt text, not sent as real API fields.
   - Stable Audio has **no "sing these exact lyrics" parameter**. If the
     user provided lyrics, they're appended to the prompt as thematic
     context only - there is no guarantee, and no claim made, that the
     output audio actually sings those words.
   - Output format requested is `mp3`; if the account/model requires a
     different format, `extensionFor()` in `index.ts` already handles
     mp3/wav/m4a, but the `stability_provider.ts` request itself would need
     updating.

## Settings → provider mapping

| Setting | Stable Audio mapping |
|---|---|
| Genre / Mood / Tempo | folded into the prompt text (no native parameters) |
| Vocal type (instrumental/male/female) | folded into the prompt text ("instrumental, no vocals" / "male vocals" / ...) |
| Language | stored in metadata only - not sent to the provider (no native parameter, and the provider doesn't sing lyrics anyway) |
| Duration short/medium/long | `duration` = 30 / 90 / 180 seconds |
| Lyrics | appended to the prompt as thematic context (see gaps above) |

## Storage

Generated audio is stored in the existing private `app-storage` bucket at
`{user_id}/generations/{request_id}/result.{mp3\|wav\|m4a}` - same
convention as images, extension chosen from the provider's actual
`Content-Type` (never assumed). The Flutter app only ever receives a signed
URL (1 hour expiry). The storage path is kept in
`generations.metadata.storagePath` so `deleteGenerationAndFiles()` (Phase 2,
reused) can remove it on delete.

## "Generate Lyrics Automatically"

Reuses Phase 1's text-generation architecture exactly - no new lyrics
pipeline was built. When enabled and the Lyrics field is empty at generate
time, the screen calls the existing
`textGenerationServiceProvider.generate(...)` (currently the Phase 1 mock
text provider) with a prompt asking for short, singable lyrics based on the
music prompt, fills the result into the Lyrics field, then proceeds with
music generation exactly as if the user had typed those lyrics themselves.

## How to test

```bash
flutter analyze
flutter test
```

To exercise the real pipeline end to end in mock mode (no key needed): sign
in, go to Create → Music, enter a prompt, tap Generate Music. A short
synthesized melody should appear in the detail screen with a working
player, tagged `mock`/`mock-music-v1`, and show up in History → filter:
Music.

**Known testing gap:** live authenticated round-trip testing of
`generate-music` (the same way `generate-image` was verified live in Phase
2 - see that document) could not be completed in this session because
Supabase's auth email-send rate limit was hit creating a second test user
shortly after Phase 2's test. What *was* verified live: an unauthenticated
request to `generate-music` correctly returns `401` from the gateway
(`verify_jwt: true` is working), and the identical architecture pattern
(auth, credits, provider call, Storage upload, signed URL) was fully
verified live for `generate-image`. The Dart-side `EdgeFunctionMusicProvider`
and the Edge Function's request/response contract are covered by unit tests
instead. Re-run the same live test Phase 2 used (create a confirmed test
user, call the function with its JWT) once the rate limit clears, to close
this gap.

There is currently no automated test runner for the Deno Edge Function code
itself (`index.ts`/`providers/*.ts`) - this matches Phase 2, which also has
no Deno-side tests. Credit-check and duplicate-request logic there are
covered by code review and the live `generate-image` verification of the
identical pattern, not by an automated Deno test suite.

## Deployment

```bash
supabase link --project-ref <your-project-ref>
supabase functions deploy generate-music
```
(For this project, it's already deployed - see the README's Supabase
configuration table.)
