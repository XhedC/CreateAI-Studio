import type { ImageGenerationProvider } from "./provider.ts";
import { MockImageProvider } from "./mock_provider.ts";
import { OpenAiImageProvider } from "./openai_provider.ts";
import { ProviderError } from "../types.ts";

/**
 * Resolves which concrete provider backs this request, based entirely on
 * Supabase Edge Function secrets - never on anything the client sends.
 *
 *   AI_IMAGE_PROVIDER = "mock" | "openai"   (default: "mock")
 *   AI_IMAGE_MODEL     = provider-specific model id (default depends on provider)
 *   AI_IMAGE_API_KEY   = provider secret key (falls back to OPENAI_API_KEY)
 *
 * Unset or "mock" -> always safe, never calls a paid API. Setting
 * AI_IMAGE_PROVIDER=openai without a configured key is a deployment mistake,
 * not a silent fallback - it fails loudly so it's caught in testing rather
 * than quietly serving mock images in production.
 */
export function resolveProvider(): ImageGenerationProvider {
  const providerName = (Deno.env.get("AI_IMAGE_PROVIDER") ?? "mock")
    .trim()
    .toLowerCase();

  switch (providerName) {
    case "mock":
    case "":
      return new MockImageProvider();

    case "openai": {
      const apiKey = Deno.env.get("AI_IMAGE_API_KEY") ??
        Deno.env.get("OPENAI_API_KEY");
      if (!apiKey) {
        throw new ProviderError(
          "AI_IMAGE_PROVIDER is set to 'openai' but no AI_IMAGE_API_KEY " +
            "(or OPENAI_API_KEY) secret is configured. Set it with " +
            "`supabase secrets set AI_IMAGE_API_KEY=...` or switch " +
            "AI_IMAGE_PROVIDER back to 'mock'.",
          "CONFIGURATION_ERROR",
        );
      }
      const model = Deno.env.get("AI_IMAGE_MODEL") ?? "gpt-image-1";
      return new OpenAiImageProvider(apiKey, model);
    }

    default:
      throw new ProviderError(
        `Unknown AI_IMAGE_PROVIDER: ${providerName}. Expected mock or openai.`,
        "CONFIGURATION_ERROR",
      );
  }
}
