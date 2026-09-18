import type {
  GeneratedVideoFile,
  GeneratedThumbnail,
  JobCreationResult,
  JobStatusResult,
  VideoSettings,
} from '../types.ts';

export interface VideoJobRequest {
  prompt: string;
  settings: VideoSettings;
  /** Reference image bytes, already downloaded server-side, if provided. */
  referenceImage?: { bytes: Uint8Array; mimeType: string } | null;
}

/**
 * Every AI video vendor integration implements this - mirrors
 * `ImageGenerationProvider`/`MusicGenerationProvider` and the Flutter-side
 * `VideoAIProvider`, so swapping vendors later is a one-file change.
 *
 * Split into two methods (unlike the synchronous image/music providers)
 * because real video generation is genuinely asynchronous: `createJob()`
 * submits the request and returns immediately with a job id; `checkStatus()`
 * is called repeatedly (by the separate `video-status` Edge Function, itself
 * polled by the Flutter app on a timer) until the provider reports a final
 * result. See docs/video-generation.md for why this project polls rather
 * than holding one long-lived mobile HTTP request open, and what a
 * webhook-based alternative would look like.
 */
export interface VideoGenerationProvider {
  readonly name: string;
  createJob(request: VideoJobRequest): Promise<JobCreationResult>;
  checkStatus(jobId: string): Promise<JobStatusResult>;
}

export type { GeneratedVideoFile, GeneratedThumbnail };
