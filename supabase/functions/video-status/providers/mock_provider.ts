import type { VideoGenerationProvider, VideoJobRequest } from './provider.ts';
import type { JobCreationResult, JobStatusResult } from '../types.ts';
import { ProviderError } from '../types.ts';

// A small, long-standing Google-hosted sample clip (used in Google's own
// ExoPlayer/media documentation) - not affiliated with any AI provider, just
// a stand-in "video" so mock mode can exercise the full
// job -> poll -> download -> upload pipeline without a real API. No paid
// API is ever called in mock mode.
const SAMPLE_VIDEO_URL =
  'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4';

const DIMENSIONS: Record<string, { width: number; height: number }> = {
  '16:9': { width: 1280, height: 720 },
  '9:16': { width: 720, height: 1280 },
  '1:1': { width: 1080, height: 1080 },
};

// How long (ms) a mock job pretends to take before it's "done" - long
// enough to exercise real polling (a couple of round trips), short enough
// not to make development tedious.
const SIMULATED_PROCESSING_MS = 9000;

/**
 * Development-mode stand-in used whenever VIDEO_GENERATION_PROVIDER is
 * unset or explicitly "mock". No paid API is called. Job state is encoded
 * entirely inside the returned jobId string (Edge Functions are stateless
 * between invocations) - see the format in createJob().
 */
export class MockVideoProvider implements VideoGenerationProvider {
  readonly name = 'mock';

  async createJob(request: VideoJobRequest): Promise<JobCreationResult> {
    const aspectRatio = request.settings.aspectRatio ?? '16:9';
    const jobId = `mock:${Date.now()}:${aspectRatio}`;
    return {
      jobId,
      providerName: this.name,
      modelName: 'mock-video-v1',
      metadata: { mock: true },
    };
  }

  async checkStatus(jobId: string): Promise<JobStatusResult> {
    const parts = jobId.split(':');
    if (parts[0] !== 'mock' || parts.length < 3) {
      throw new ProviderError('Unknown mock job id.', 'JOB_NOT_FOUND');
    }
    const startedAt = Number(parts[1]);
    const aspectRatio = parts[2];
    if (!Number.isFinite(startedAt)) {
      throw new ProviderError('Unknown mock job id.', 'JOB_NOT_FOUND');
    }

    if (Date.now() - startedAt < SIMULATED_PROCESSING_MS) {
      return { status: 'processing' };
    }

    const { width, height } = DIMENSIONS[aspectRatio] ?? DIMENSIONS['16:9'];

    const videoResponse = await fetch(SAMPLE_VIDEO_URL);
    if (!videoResponse.ok) {
      return {
        status: 'failed',
        error: 'The development video provider is temporarily unavailable.',
      };
    }
    const videoBytes = new Uint8Array(await videoResponse.arrayBuffer());

    const thumbLabel = encodeURIComponent('Mock Video');
    const thumbResponse = await fetch(
      `https://placehold.co/${width}x${height}/6750F4/FFFFFF/png?text=${thumbLabel}`,
    );
    const thumbnail = thumbResponse.ok
      ? {
          bytes: new Uint8Array(await thumbResponse.arrayBuffer()),
          mimeType: 'image/png',
        }
      : undefined;

    return {
      status: 'completed',
      video: { bytes: videoBytes, mimeType: 'video/mp4' },
      thumbnail,
      metadata: {
        mock: true,
        note:
          'Placeholder output from the development provider - no paid AI API was called.',
      },
    };
  }
}
