import type { FunnelBusinessInfo, ProviderFunnelResult } from "../types.ts";

/** What every concrete funnel-generation vendor implementation receives.
 * Image URLs are already-resolved signed URLs (or null) - the provider only
 * needs to know they exist for context; the Edge Function itself is
 * responsible for splicing the real URLs into the validated result
 * afterward, so a provider can never "forget" or hallucinate them. */
export interface FunnelProviderRequest {
  prompt: string;
  funnelType: string;
  businessInfo: FunnelBusinessInfo;
  hasLogo: boolean;
  hasProductImage: boolean;
}

/** The abstraction every AI vendor must implement to produce a structured
 * funnel. Deliberately not coupled to any one LLM vendor - see
 * docs/funnel-generation.md. */
export interface FunnelGenerationProvider {
  generate(request: FunnelProviderRequest): Promise<ProviderFunnelResult>;
}
