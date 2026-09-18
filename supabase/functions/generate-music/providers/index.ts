import type { MusicGenerationProvider } from './provider.ts';
import { MockMusicProvider } from './mock_provider.ts';
import { StabilityMusicProvider } from './stability_provider.ts';
import { ProviderError } from '../types.ts';

/**
 * Resolves which concrete provider backs this request, based entirely on
 * Supabase Edge Function secrets - never on anything the client sends.
 * Mirrors generate-image/providers/index.ts.
 *
 *   MUSIC_GENERATION_PROVIDER = "mock" | "stability"   (default: "mock")
 *   MUSIC_GENERATION_MODEL     = provider-specific model id
 *   MUSIC_GENERATION_API_KEY   = provider secret key (falls back to STABILITY_API_KEY)
 *
 * Unset or "mock" -> always safe, never calls a paid API. Setting
 * MUSIC_GENERATION_PROVIDER=stability without a configured key fails loudly
 * instead of silently serving mock audio in production.
 */
export function resolveProvider(): MusicGenerationProvider {
  const providerName = (Deno.env.get('MUSIC_GENERATION_PROVIDER') ?? 'mock')
    .trim()
    .toLowerCase();

  switch (providerName) {
    case 'mock':
    case '':
      return new MockMusicProvider();

    case 'stability': {
      const apiKey = Deno.env.get('MUSIC_GENERATION_API_KEY') ??
        Deno.env.get('STABILITY_API_KEY');
      if (!apiKey) {
        throw new ProviderError(
          "MUSIC_GENERATION_PROVIDER is set to 'stability' but no " +
            'MUSIC_GENERATION_API_KEY (or STABILITY_API_KEY) secret is ' +
            'configured. Set it with `supabase secrets set ' +
            'MUSIC_GENERATION_API_KEY=...` or switch MUSIC_GENERATION_PROVIDER ' +
            "back to 'mock'.",
          'CONFIGURATION_ERROR',
        );
      }
      const model = Deno.env.get('MUSIC_GENERATION_MODEL') ?? 'stable-audio-2';
      return new StabilityMusicProvider(apiKey, model);
    }

    default:
      throw new ProviderError(
        `Unknown MUSIC_GENERATION_PROVIDER: ${providerName}. Expected mock or stability.`,
        'CONFIGURATION_ERROR',
      );
  }
}
