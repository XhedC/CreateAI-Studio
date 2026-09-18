// Shared request/response contracts for the generate-music Edge Function.
// Mirrors supabase/functions/generate-image/types.ts - see that file's
// comments for the overall pattern.

export interface MusicSettings {
  genre: string;
  mood: string;
  vocalType: 'male' | 'female' | 'instrumental';
  language: string;
  duration: 'short' | 'medium' | 'long';
  tempo: string;
  instrumental: boolean;
}

export interface GenerateMusicRequestBody {
  generationId: string;
  prompt: string;
  lyrics?: string | null;
  settings?: Partial<MusicSettings>;
}

export interface GeneratedAudioFile {
  /** Raw audio bytes returned by the provider, before upload. */
  bytes: Uint8Array;
  mimeType: string;
  /** Provider-reported duration in seconds, if known. */
  durationSeconds?: number;
}

export interface ProviderGenerationResult {
  audio: GeneratedAudioFile;
  /** e.g. "stability", "mock" - stored in generations.provider */
  providerName: string;
  /** e.g. "stable-audio-2", "mock-music-v1" - stored in generations.model */
  modelName: string;
  /** Provider-specific extras merged into generations.metadata. */
  metadata: Record<string, unknown>;
}

export class ProviderError extends Error {
  constructor(
    message: string,
    public readonly code:
      | 'INVALID_PROMPT'
      | 'INVALID_LYRICS'
      | 'PROVIDER_ERROR'
      | 'TIMEOUT'
      | 'RATE_LIMITED'
      | 'UNSUPPORTED_FORMAT'
      | 'CONFIGURATION_ERROR',
  ) {
    super(message);
    this.name = 'ProviderError';
  }
}
