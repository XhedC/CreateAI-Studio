// Shared request/response contracts for the generate-funnel Edge Function.
// See docs/funnel-generation.md for the full schema this describes.

export interface FunnelBusinessInfo {
  businessName?: string;
  businessType?: string;
  product?: string;
  targetAudience?: string;
  goal?: string;
  offer?: string;
  cta?: string;
}

export interface GenerateFunnelRequestBody {
  generationId: string;
  prompt: string;
  funnelType?: string;
  businessInfo?: FunnelBusinessInfo;
  logoPath?: string | null;
  productImagePath?: string | null;
  referenceImagePath?: string | null;
}

export interface FunnelTheme {
  primaryColor: string;
  secondaryColor: string;
  backgroundColor: string;
  textColor: string;
  fontFamily: string;
  logoUrl?: string | null;
}

export interface FunnelSeo {
  title: string;
  description: string;
  ogTitle: string;
  ogDescription: string;
}

export interface FunnelSettings {
  showNavigation: boolean;
  enableLeadCapture: boolean;
}

export interface FunnelMetadata {
  business_name: string;
  business_type: string;
  target_audience: string;
  goal: string;
  offer: string;
  cta: string;
}

export interface FunnelSection {
  id: string;
  type: string;
  visible: boolean;
  content: Record<string, unknown>;
}

/** The validated, versioned funnel document - the single source of truth
 * stored in `funnels.content`. Never store anything that didn't pass
 * `validateFunnelResponse()` (see schema.ts). */
export interface FunnelSchema {
  version: number;
  name: string;
  type: string;
  metadata: FunnelMetadata;
  theme: FunnelTheme;
  sections: FunnelSection[];
  seo: FunnelSeo;
  settings: FunnelSettings;
}

/** What a concrete AI vendor implementation hands back - `raw` is whatever
 * (possibly malformed) JSON-ish value the model produced; schema.ts is
 * responsible for validating/correcting it into a FunnelSchema. */
export interface ProviderFunnelResult {
  raw: unknown;
  providerName: string;
  modelName: string;
  metadata: Record<string, unknown>;
}

export class ProviderError extends Error {
  constructor(
    message: string,
    public readonly code:
      | "INVALID_PROMPT"
      | "INVALID_REQUEST"
      | "INVALID_AI_RESPONSE"
      | "PROVIDER_ERROR"
      | "TIMEOUT"
      | "RATE_LIMITED"
      | "CONFIGURATION_ERROR",
  ) {
    super(message);
    this.name = "ProviderError";
  }
}
