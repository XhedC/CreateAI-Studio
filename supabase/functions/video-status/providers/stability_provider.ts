import type { VideoGenerationProvider, VideoJobRequest } from './provider.ts';
import type { JobCreationResult, JobStatusResult } from '../types.ts';
import { ProviderError } from '../types.ts';

const CREATE_JOB_URL = 'https://api.stability.ai/v2beta/image-to-video';
const RESULT_URL = (id: string) =>
  `https://api.stability.ai/v2beta/image-to-video/result/${id}`;

// Stable Video Diffusion has no discrete "motion" enum - it takes a numeric
// motion_bucket_id. This is our own mapping, not a value the provider
// documents as canonical.
const MOTION_BUCKET_ID: Record<string, number> = {
  low: 80,
  medium: 127,
  high: 180,
};

/**
 * Real AI vendor integration - Stability AI's Stable Video Diffusion API,
 * implemented against its publicly documented v2beta image-to-video
 * endpoint as of this writing. Re-verify against
 * https://platform.stability.ai/docs/api-reference before relying on this
 * in production - see docs/video-generation.md.
 *
 * IMPORTANT capability gap (documented, not silently pretended to work):
 * Stable Video Diffusion is **image-to-video only** - it has no
 * text-to-video mode. `createJob()` throws a clear, friendly
 * `MISSING_REFERENCE_IMAGE` error if no reference image was provided,
 * rather than silently ignoring the prompt and generating something
 * unrelated. Aspect ratio, resolution, duration, style, and fps have no
 * native parameters either - the model outputs a fixed short clip at its
 * own resolution; those settings are recorded in metadata for the record
 * but are not sent to (or honored by) this provider. No thumbnail is
 * returned by this provider - thumbnail extraction from the video itself is
 * not implemented (documented gap, not attempted).
 */
export class StabilityVideoProvider implements VideoGenerationProvider {
  readonly name = 'stability';

  constructor(
    private readonly apiKey: string,
    private readonly model: string,
  ) {}

  async createJob(request: VideoJobRequest): Promise<JobCreationResult> {
    if (!request.referenceImage) {
      throw new ProviderError(
        'This video provider requires a reference image (image-to-video only). ' +
          'Please upload an image, or use mock mode for text-to-video.',
        'MISSING_REFERENCE_IMAGE',
      );
    }

    const form = new FormData();
    form.set(
      'image',
      new Blob([request.referenceImage.bytes], { type: request.referenceImage.mimeType }),
      'reference.png',
    );
    form.set(
      'motion_bucket_id',
      String(MOTION_BUCKET_ID[request.settings.motion] ?? MOTION_BUCKET_ID.medium),
    );

    let response: Response;
    try {
      response = await fetch(CREATE_JOB_URL, {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.apiKey}` },
        body: form,
      });
    } catch {
      throw new ProviderError(
        'Could not reach the AI video provider. Please try again.',
        'PROVIDER_ERROR',
      );
    }

    if (!response.ok) {
      if (response.status === 429) {
        throw new ProviderError(
          'The AI video provider is rate-limited. Please try again shortly.',
          'RATE_LIMITED',
        );
      }
      const detail = await safeErrorMessage(response);
      throw new ProviderError(
        `The AI video provider returned an error: ${detail}`,
        'PROVIDER_ERROR',
      );
    }

    const data = await response.json();
    if (typeof data?.id !== 'string') {
      throw new ProviderError(
        'The AI video provider did not return a job id.',
        'PROVIDER_ERROR',
      );
    }

    return {
      jobId: data.id,
      providerName: this.name,
      modelName: this.model,
      metadata: {
        motionBucketId: MOTION_BUCKET_ID[request.settings.motion] ?? MOTION_BUCKET_ID.medium,
      },
    };
  }

  async checkStatus(jobId: string): Promise<JobStatusResult> {
    let response: Response;
    try {
      response = await fetch(RESULT_URL(jobId), {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          Accept: 'video/*',
        },
      });
    } catch {
      throw new ProviderError(
        'Could not reach the AI video provider. Please try again.',
        'PROVIDER_ERROR',
      );
    }

    if (response.status === 202) {
      return { status: 'processing' };
    }
    if (response.status === 404) {
      return { status: 'failed', error: 'This video job could not be found.' };
    }
    if (!response.ok) {
      const detail = await safeErrorMessage(response);
      return { status: 'failed', error: `The AI video provider returned an error: ${detail}` };
    }

    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0) {
      return { status: 'failed', error: 'The AI video provider did not return any video.' };
    }

    return {
      status: 'completed',
      video: { bytes, mimeType: 'video/mp4' },
      // No native thumbnail from this provider - see class doc comment.
      metadata: {},
    };
  }
}

async function safeErrorMessage(response: Response): Promise<string> {
  try {
    const body = await response.json();
    return typeof body?.errors?.[0] === 'string'
      ? body.errors[0]
      : typeof body?.message === 'string'
        ? body.message
        : `HTTP ${response.status}`;
  } catch {
    return `HTTP ${response.status}`;
  }
}
