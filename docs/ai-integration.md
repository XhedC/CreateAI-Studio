# AI integration architecture

Phase 1 shipped a complete generation pipeline with every AI call mocked.
Phase 2 connected the **Image** category to a real backend (a Supabase Edge
Function, with a provider-agnostic vendor abstraction behind it) as the
worked example of this document's plan - see
[image-generation.md](image-generation.md) for that implementation in full.
Phase 3 repeated the exact same pattern for **Music** - see
[music-generation.md](music-generation.md). Phase 4 repeated it again for
**Video** - see [video-generation.md](video-generation.md) - with one
architectural addition: video is the first genuinely asynchronous provider
(job created, then polled to completion), so the abstraction below gained
an `isPending` result flag to support it. Phase 5 repeated it once more
for **Funnel** - see [funnel-generation.md](funnel-generation.md) - with a
second small addition: `AIGenerationRequest` gained a `generationId` field,
since a funnel's real result is a new row in its own `funnels` table
(linked back to the generation that requested it), not something that
fits into `generations`' own columns. Text remains mocked, unchanged,
pending a later phase.

## The abstraction

```
lib/features/generation/services/
  ai_provider.dart                  # AIProvider interface + per-type interfaces + request/result types
  mock_ai_provider.dart             # Mock*AIProvider - still used by Text/Video/Funnel
  edge_function_image_provider.dart # real ImageAIProvider - calls the generate-image Edge Function (Phase 2)
  edge_function_music_provider.dart # real MusicAIProvider - calls the generate-music Edge Function (Phase 3)
  edge_function_video_provider.dart # real VideoAIProvider - starts a generate-video job (Phase 4, async)
  video_status_checker.dart         # polls the video-status Edge Function (Phase 4)
  edge_function_funnel_provider.dart # real FunnelAIProvider - calls generate-funnel (Phase 5)
  text_generation_service.dart      # thin per-type wrapper (+ image/music/video/funnel siblings)
  generation_service.dart           # shared base for the *GenerationService wrappers
  generation_orchestrator.dart      # the one reusable workflow every creation type goes through
  file_upload_service.dart          # uploads user attachments to Supabase Storage
```

```
abstract class AIProvider {
  CreationType get type;
  String get providerName;   // stored in generations.provider
  String get modelName;      // stored in generations.model
  Future<AIGenerationResult> generate(AIGenerationRequest request);
}

abstract class TextAIProvider implements AIProvider { ... }
abstract class ImageAIProvider implements AIProvider { ... }
abstract class MusicAIProvider implements AIProvider { ... }
abstract class VideoAIProvider implements AIProvider { ... }
abstract class FunnelAIProvider implements AIProvider { ... }
```

`AIGenerationRequest` carries the prompt, any uploaded attachment URLs, and an
`options` map reserved for future advanced controls (aspect ratio, voice,
tone, duration, ...) - providers read the keys they understand and ignore the
rest, so the UI can grow this map without a breaking change.

`AIGenerationResult` is what a provider hands back:
`resultText`/`resultUrl`/`thumbnailUrl`/`metadata` (jsonb-compatible map),
plus an optional `additionalFiles` list (added in Phase 2) for providers
that can return more than one output per request - each entry is persisted
into the existing `generation_files` table via
`GenerationRepository.attachFile`. Nothing that doesn't set this field
behaves any differently. `metadata` may also carry `provider`/`model` keys
when the *actual* backend isn't known until the call returns (e.g. a
backend that can serve either a mock or a real vendor) -
`GenerationOrchestrator` prefers those over the static
`provider.providerName`/`modelName` getters when present.

`AIGenerationResult.isPending` (added in Phase 4, default `false`): set to
`true` when a provider has only *started* a job and has no result yet - the
orchestrator leaves the generation's status as `processing` (instead of
`completed`) and just records the job id/metadata, rather than treating the
call as finished. Every provider from Phase 1-3 leaves this at its default
and behaves exactly as before; only `EdgeFunctionVideoProvider` sets it.
This is what makes the abstraction support genuinely asynchronous providers
without changing `AIProvider`'s method signature or any other provider's
code - see [video-generation.md](video-generation.md)'s "Async generation
architecture" for the full poll-to-completion flow that takes over once a
result is pending.

`AIGenerationRequest.generationId` (added in Phase 5, default `null`): the id of the `generations` row a request is
fulfilling, set by `GenerationOrchestrator` right before calling the
provider. Every provider except `EdgeFunctionFunnelProvider` ignores it;
funnel generation needs it because its real result is a *new row in a
different table* (`funnels`), which its Edge Function must link back to
the originating generation server-side - see
[funnel-generation.md](funnel-generation.md)'s "Why the orchestrator
needed one new field."

## The workflow (`GenerationOrchestrator`)

```
validate prompt
  -> check connectivity (NetworkService)
  -> create `generations` row, status = pending
  -> status = processing
  -> call the AIProvider for the requested CreationType
  -> success: persist result_text/result_url/thumbnail_url/metadata, status = completed
  -> failure: persist error_message, status = failed
```

This class is the **only** thing the UI talks to
(`createGenerationControllerProvider` in
`generation/presentation/providers/generation_providers.dart` wraps it for
Riverpod). It never imports a concrete provider - only the
`Map<CreationType, AIProvider>` it's constructed with.

## Wiring: where "which provider backs which type" is decided

`lib/features/generation/presentation/providers/generation_providers.dart`:

```dart
// Phase 2-5: Image, Music, Video, and Funnel are all wired to their real
// backends. Text is still mocked - swapping it follows the exact same
// one-line pattern shown here.
final imageAIProviderProvider = Provider<ImageAIProvider>(
  (ref) => EdgeFunctionImageProvider(ref.watch(supabaseClientProvider)),
);
final musicAIProviderProvider = Provider<MusicAIProvider>(
  (ref) => EdgeFunctionMusicProvider(ref.watch(supabaseClientProvider)),
);
final videoAIProviderProvider = Provider<VideoAIProvider>(
  (ref) => EdgeFunctionVideoProvider(ref.watch(supabaseClientProvider)),
);
final funnelAIProviderProvider = Provider<FunnelAIProvider>(
  (ref) => EdgeFunctionFunnelProvider(ref.watch(supabaseClientProvider)),
);
...
final generationOrchestratorProvider = Provider<GenerationOrchestrator>((ref) {
  return GenerationOrchestrator(
    ...
    providersByType: {
      CreationType.image: ref.watch(imageGenerationServiceProvider).provider,
      ...
    },
  );
});
```

Changing which concrete provider backs a category is a one-line change to
one of these `Provider<XAIProvider>` declarations. No screen, repository,
router, or database code changes - this is exactly what happened when Image
moved from `MockImageAIProvider()` to `EdgeFunctionImageProvider(...)` in
Phase 2.

## Adding a real provider (worked example: image generation, Phase 2)

This is what actually happened, not a hypothetical - see
[image-generation.md](image-generation.md) for the full picture.

1. **Never call the AI vendor's API from Flutter directly.** A Supabase Edge
   Function, `generate-image` (`supabase/functions/generate-image/`),
   receives `{ prompt, referenceImagePath, settings }`, derives the caller's
   identity from their JWT (never the request body), calls the vendor with a
   key that only exists as an Edge Function secret, uploads the result to
   Storage, and returns `{ success, images: [...], provider, model, metadata }`.
   It deliberately does *not* touch the `generations` table - see
   image-generation.md's "why" section.
2. Implement the interface in Flutter
   (`lib/features/generation/services/edge_function_image_provider.dart`):
   ```dart
   class EdgeFunctionImageProvider implements ImageAIProvider {
     EdgeFunctionImageProvider(SupabaseClient client)
         : _invoke = client.functions.invoke;

     @override
     CreationType get type => CreationType.image;
     // The real provider/model (mock vs. openai) isn't known until the
     // Edge Function responds - see the metadata note above.
     @override
     String get providerName => 'unknown';
     @override
     String get modelName => 'unknown';

     @override
     Future<AIGenerationResult> generate(AIGenerationRequest request) async {
       final response = await _invoke('generate-image', body: {
         'prompt': request.prompt,
         'referenceImagePath':
             request.attachmentUrls.isNotEmpty ? request.attachmentUrls.first : null,
         'settings': request.options,
       });
       // ...map response.data into AIGenerationResult (see the real file
       // for full error handling).
     }
   }
   ```
3. Swap the provider in `generation_providers.dart` (the one-line change
   shown above).
4. Done. `GenerationOrchestrator`, the Create screen, History, Project
   detail, and the database schema are all unchanged.

## Request routing ("what type of generation is this?")

Phase 1 has the user pick the creation type explicitly on the Create screen
(`CreationTypeSelector`) - there is no free-text intent classifier yet. A
future phase can add one as another small service
(`lib/features/generation/services/intent_router_service.dart`, say) that
takes a raw prompt like *"Create a modern advertisement for a pharmacy"* and
returns a `CreationType`, called before `GenerationOrchestrator.generate()` -
it plugs into the same `Map<CreationType, AIProvider>` wiring without
changing the orchestrator.

## File uploads

`FileUploadService` uploads picked files to the private `app-storage` bucket
under `{user_id}/uploads/...` and returns both a `storagePath` and a
short-lived signed `publicUrl`. For the image generator, it's the
**storage path** (not the signed URL, which can expire before an Edge
Function call completes) that gets passed as
`AIGenerationRequest.attachmentUrls` - the Edge Function re-downloads the
file itself via a Supabase client scoped to the caller's own JWT, so Storage
RLS applies to that read exactly as it would to any other request from that
user.
