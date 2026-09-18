import type {
  GeneratedAudioFile,
  MusicSettings,
  ProviderGenerationResult,
} from '../types.ts';

export interface MusicGenerationRequest {
  prompt: string;
  lyrics: string | null;
  settings: MusicSettings;
}

/**
 * Every AI music vendor integration implements this - mirrors
 * `ImageGenerationProvider` in generate-image and `MusicAIProvider` on the
 * Flutter side (lib/features/generation/services/ai_provider.dart), so
 * swapping vendors later is a one-file change, not an architecture change.
 *
 * `generate()` returns the *final* audio, synchronously from the caller's
 * point of view. A provider whose real API is job-based/asynchronous
 * (submit job -> poll status -> download) is expected to do that polling
 * internally, bounded by a timeout, and throw `ProviderError('...', 'TIMEOUT')`
 * if the job doesn't finish in time - see docs/music-generation.md for why
 * this project doesn't hold a single long-lived mobile HTTP request open for
 * generation, and what a webhook-based alternative would look like.
 */
export interface MusicGenerationProvider {
  readonly name: string;
  generate(request: MusicGenerationRequest): Promise<ProviderGenerationResult>;
}
