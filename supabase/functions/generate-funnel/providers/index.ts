import type { FunnelGenerationProvider } from "./provider.ts";
import { MockFunnelProvider } from "./mock_provider.ts";
import { OpenAiFunnelProvider } from "./openai_provider.ts";
import { ProviderError } from "../types.ts";

/**
 * Resolves which concrete provider backs this request, based entirely on
 * Supabase Edge Function secrets - never on anything the client sends.
 *
 *   FUNNEL_GENERATION_PROVIDER = "mock" | "openai"   (default: "mock")
 *   FUNNEL_GENERATION_MODEL     = provider-specific model id (default: "gpt-4o-mini")
 *   FUNNEL_GENERATION_API_KEY   = provider secret key (falls back to OPENAI_API_KEY)
 *
 * Unset or "mock" -> always safe, never calls a paid API. Setting
 * FUNNEL_GENERATION_PROVIDER=openai without a configured key fails loudly
 * rather than silently falling back to mock output.
 */
export function resolveProvider(): FunnelGenerationProvider {
  const providerName = (Deno.env.get("FUNNEL_GENERATION_PROVIDER") ?? "mock")
    .trim()
    .toLowerCase();

  switch (providerName) {
    case "mock":
    case "":
      return new MockFunnelProvider();

    case "openai": {
      const apiKey = Deno.env.get("FUNNEL_GENERATION_API_KEY") ??
        Deno.env.get("OPENAI_API_KEY");
      if (!apiKey) {
        throw new ProviderError(
          "FUNNEL_GENERATION_PROVIDER is set to 'openai' but no " +
            "FUNNEL_GENERATION_API_KEY (or OPENAI_API_KEY) secret is " +
            "configured. Set it with `supabase secrets set " +
            "FUNNEL_GENERATION_API_KEY=...` or switch " +
            "FUNNEL_GENERATION_PROVIDER back to 'mock'.",
          "CONFIGURATION_ERROR",
        );
      }
      const model = Deno.env.get("FUNNEL_GENERATION_MODEL") ?? "gpt-4o-mini";
      return new OpenAiFunnelProvider(apiKey, model);
    }

    default:
      throw new ProviderError(
        `Unknown FUNNEL_GENERATION_PROVIDER: ${providerName}. Expected mock or openai.`,
        "CONFIGURATION_ERROR",
      );
  }
}
