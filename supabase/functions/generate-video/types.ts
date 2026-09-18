// Shared request/response contracts for the generate-video and video-status
// Edge Functions. Mirrors generate-image/types.ts and generate-music/types.ts
// - see those files' comments for the overall pattern. Video is genuinely
// asynchronous (unlike the synchronous image/music providers connected so
// far), so the contract here is split into "start a job" and "check a job"
// rather than one generate() call - see providers/provider.ts.

export interface VideoSettings {
  aspectRatio: '16:9' | '9:16' | '1:1';
  resolution: '720p' | '1080p';
  duration: 'short' | 'medium' | 'long';
  motion: 'low' | 'medium' | 'high';
  style: string;
  fps: 24 | 30;
}

export interface GenerateVideoRequestBody {
  prompt: string;
  referenceImagePath?: string | null;
  settings?: Partial<VideoSettings>;
}

export interface VideoStatusRequestBody {
  generationId: string;
  jobId: string;
}

export interface GeneratedVideoFile {
  bytes: Uint8Array;
  mimeType: string;
  durationSeconds?: number;
}

export interface GeneratedThumbnail {
  bytes: Uint8Array;
  mimeType: string;
}

/** Returned immediately when a job is created - no video yet. */
export interface JobCreationResult {
  jobId: string;
  providerName: string;
  modelName: string;
  metadata: Record<string, unknown>;
}

/** Returned by a status check once the provider has a final answer. */
export type JobStatusResult =
  | { status: 'processing' }
  | {
      status: 'completed';
      video: GeneratedVideoFile;
      thumbnail?: GeneratedThumbnail;
      metadata: Record<string, unknown>;
    }
  | { status: 'failed'; error: string };

export class ProviderError extends Error {
  constructor(
    message: string,
    public readonly code:
      | 'INVALID_PROMPT'
      | 'INVALID_REQUEST'
      | 'MISSING_REFERENCE_IMAGE'
      | 'PROVIDER_ERROR'
      | 'TIMEOUT'
      | 'RATE_LIMITED'
      | 'JOB_NOT_FOUND'
      | 'CONFIGURATION_ERROR',
  ) {
    super(message);
    this.name = 'ProviderError';
  }
}
