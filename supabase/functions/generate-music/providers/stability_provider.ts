import type { MusicGenerationProvider, MusicGenerationRequest } from './provider.ts';
import type { ProviderGenerationResult } from '../types.ts';
import { ProviderError } from '../types.ts';

const TEXT_TO_AUDIO_URL =
  'https://api.stability.ai/v2beta/audio/stable-audio-2/text-to-audio';

// Stable Audio has no discrete genre/mood/vocal-type/tempo/language
// parameters - it's a free-text-prompt model - so those settings are folded
// into the prompt text instead of sent as real fields (documented, not
// pretended). It also has no dedicated "sing these exact lyrics" parameter;
// if the user provided lyrics, they're appended as thematic/lyrical context
// for the prompt, not guaranteed to be sung verbatim.
const DURATION_SECONDS: Record<string, number> = {
  short: 30,
  medium: 90,
  long: 180,
};

/**
 * Real AI vendor integration - Stability AI's Stable Audio API
 * (`stable-audio-2`), implemented against its publicly documented
 * text-to-audio endpoint as of this writing. Re-verify against
 * https://platform.stability.ai/docs/api-reference before relying on this
 * in production - see docs/music-generation.md.
 *
 * Unlike the image provider's OpenAI integration, this endpoint is
 * synchronous: one request returns the final audio directly (no job/poll
 * cycle), so no async-job handling is needed here. A future provider that
 * *is* job-based should poll internally within `generate()`, bounded by a
 * timeout, and throw `ProviderError(..., 'TIMEOUT')` if it doesn't finish in
 * time - see provider.ts and docs/music-generation.md for the pattern this
 * project uses instead of holding one long-lived mobile HTTP request open.
 */
export class StabilityMusicProvider implements MusicGenerationProvider {
  readonly name = 'stability';

  constructor(
    private readonly apiKey: string,
    private readonly model: string,
  ) {}

  async generate(
    request: MusicGenerationRequest,
  ): Promise<ProviderGenerationResult> {
    const duration = DURATION_SECONDS[request.settings.duration] ?? 90;
    const prompt = buildPrompt(request);

    const form = new FormData();
    form.set('prompt', prompt);
    form.set('duration', String(duration));
    form.set('output_format', 'mp3');

    let response: Response;
    try {
      response = await fetch(TEXT_TO_AUDIO_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          Accept: 'audio/*',
        },
        body: form,
      });
    } catch {
      throw new ProviderError(
        'Could not reach the AI music provider. Please try again.',
        'PROVIDER_ERROR',
      );
    }

    if (!response.ok) {
      if (response.status === 429) {
        throw new ProviderError(
          'The AI music provider is rate-limited. Please try again shortly.',
          'RATE_LIMITED',
        );
      }
      const detail = await safeErrorMessage(response);
      throw new ProviderError(
        `The AI music provider returned an error: ${detail}`,
        'PROVIDER_ERROR',
      );
    }

    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0) {
      throw new ProviderError(
        'The AI music provider did not return any audio.',
        'PROVIDER_ERROR',
      );
    }

    return {
      audio: { bytes, mimeType: 'audio/mpeg', durationSeconds: duration },
      providerName: this.name,
      modelName: this.model,
      metadata: {
        requestedPrompt: prompt,
        mappedDurationSeconds: duration,
        lyricsProvided: Boolean(request.lyrics?.trim()),
      },
    };
  }
}

function buildPrompt(request: MusicGenerationRequest): string {
  const parts = [request.prompt.trim()];
  const { genre, mood, tempo, instrumental, vocalType } = request.settings;
  if (genre && genre !== 'none') parts.push(`${genre} genre`);
  if (mood && mood !== 'none') parts.push(`${mood} mood`);
  if (tempo && tempo !== 'none') parts.push(`${tempo} tempo`);
  if (instrumental || vocalType === 'instrumental') {
    parts.push('instrumental, no vocals');
  } else if (vocalType) {
    parts.push(`${vocalType} vocals`);
  }
  if (request.lyrics?.trim()) {
    parts.push(`with lyrical themes: ${request.lyrics.trim().slice(0, 300)}`);
  }
  return parts.join(', ');
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
