import type { VideoGenerationProvider } from './provider.ts';
import { MockVideoProvider } from './mock_provider.ts';
import { StabilityVideoProvider } from './stability_provider.ts';
import { ProviderError } from '../types.ts';

/**
 * Resolves which concrete provider backs this request, based entirely on
 * Supabase Edge Function secrets - never on anything the client sends.
 * Mirrors generate-image/providers/index.ts and generate-music/providers/index.ts.
 *
 *   VIDEO_GENERATION_PROVIDER = mock | stability   (default: mock)
 *   VIDEO_GENERATION_MODEL     = provider-specific model id
 *   VIDEO_GENERATION_API_KEY   = provider secret key (falls back to STABILITY_API_KEY)
 *
 * Unset or mock -> always safe, never calls a paid API. Setting
 * VIDEO_GENERATION_PROVIDER=stability without a configured key fails loudly
 * instead of silently serving mock video in production.
 */
export function resolveProvider(): VideoGenerationProvider {
  const providerName = (Deno.env.get('VIDEO_GENERATION_PROVIDER') ?? 'mock')
    .trim()
    .toLowerCase();

  switch (providerName) {
    case 'mock':
    case '':
      return new MockVideoProvider();

    case 'stability': {
      const apiKey = Deno.env.get('VIDEO_GENERATION_API_KEY') ??
        Deno.env.get('STABILITY_API_KEY');
      if (!apiKey) {
        throw new ProviderError(
          "VIDEO_GENERATION_PROVIDER is set to 'stability' but no VIDEO_GENERATION_API_KEY " +
            "(or STABILITY_API_KEY) secret is configured. Set it with `supabase secrets set " +
            "VIDEO_GENERATION_API_KEY=...` or switch VIDEO_GENERATION_PROVIDER back to 'mock'.",
          'CONFIGURATION_ERROR',
        );
      }
      const model = Deno.env.get('VIDEO_GENERATION_MODEL') ?? 'stable-video-diffusion';
      return new StabilityVideoProvider(apiKey, model);
    }

    default:
      throw new ProviderError(
        `Unknown VIDEO_GENERATION_PROVIDER: ${providerName}. Expected mock or stability.`,
        'CONFIGURATION_ERROR',
      );
  }
}
