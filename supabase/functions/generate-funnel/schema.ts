// Validates and safely corrects a raw AI response into a FunnelSchema.
// Never rendered/stored without going through here first - per the brief:
// "Validate the AI output against the expected schema before rendering. If
// the response is invalid: attempt safe correction if appropriate,
// otherwise show an error. Never blindly render malformed data."

import { ProviderError } from "./types.ts";
import type {
  FunnelBusinessInfo,
  FunnelMetadata,
  FunnelSchema,
  FunnelSection,
  FunnelSeo,
  FunnelSettings,
  FunnelTheme,
} from "./types.ts";

export const VALID_FUNNEL_TYPES = [
  "lead_generation",
  "product_sales",
  "service_business",
  "appointment_booking",
  "event_registration",
  "restaurant",
  "pharmacy",
  "healthcare",
  "real_estate",
  "personal_brand",
  "agency",
  "ecommerce",
  "course",
  "portfolio",
  "custom",
];

export const VALID_GOALS = [
  "generate_leads",
  "sell_product",
  "book_appointment",
  "collect_contact_info",
  "promote_service",
  "build_brand_awareness",
  "event_registration",
  "custom",
];

// Every section type the Flutter FunnelRenderer knows how to draw. An AI
// response naming anything outside this list has that one section dropped
// (safe correction) rather than failing the whole funnel.
export const VALID_SECTION_TYPES = [
  "hero",
  "navigation",
  "benefits",
  "features",
  "services",
  "products",
  "pricing",
  "testimonials",
  "statistics",
  "about",
  "faq",
  "contact",
  "lead_form",
  "appointment_cta",
  "final_cta",
  "footer",
  "custom",
];

const DEFAULT_THEME: FunnelTheme = {
  primaryColor: "#2563EB",
  secondaryColor: "#0F172A",
  backgroundColor: "#FFFFFF",
  textColor: "#0F172A",
  fontFamily: "Inter",
};

const HEX_COLOR = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;

function str(value: unknown, fallback = ""): string {
  return typeof value === "string" && value.trim().length > 0 ? value : fallback;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function sanitizeColor(value: unknown, fallback: string): string {
  return typeof value === "string" && HEX_COLOR.test(value) ? value : fallback;
}

function sanitizeTheme(raw: unknown): FunnelTheme {
  const t = isPlainObject(raw) ? raw : {};
  return {
    primaryColor: sanitizeColor(t.primaryColor, DEFAULT_THEME.primaryColor),
    secondaryColor: sanitizeColor(t.secondaryColor, DEFAULT_THEME.secondaryColor),
    backgroundColor: sanitizeColor(t.backgroundColor, DEFAULT_THEME.backgroundColor),
    textColor: sanitizeColor(t.textColor, DEFAULT_THEME.textColor),
    fontFamily: str(t.fontFamily, DEFAULT_THEME.fontFamily),
  };
}

function sanitizeSeo(raw: unknown, fallbackTitle: string, fallbackDescription: string): FunnelSeo {
  const s = isPlainObject(raw) ? raw : {};
  const title = str(s.title, fallbackTitle);
  const description = str(s.description, fallbackDescription);
  return {
    title,
    description,
    ogTitle: str(s.ogTitle, title),
    ogDescription: str(s.ogDescription, description),
  };
}

function sanitizeSection(raw: unknown, index: number): FunnelSection | null {
  if (!isPlainObject(raw)) return null;
  const type = typeof raw.type === "string" ? raw.type.toLowerCase() : "";
  if (!VALID_SECTION_TYPES.includes(type)) return null;
  const content = isPlainObject(raw.content) ? raw.content : {};
  return {
    id: str(raw.id, `${type}-${index}`),
    type,
    visible: raw.visible !== false,
    content,
  };
}

function sanitizeMetadata(
  raw: unknown,
  businessInfo: FunnelBusinessInfo,
): FunnelMetadata {
  const m = isPlainObject(raw) ? raw : {};
  const goal = str(businessInfo.goal ?? (m.goal as string | undefined), "custom").toLowerCase();
  return {
    business_name: str(businessInfo.businessName ?? (m.business_name as string | undefined)),
    business_type: str(businessInfo.businessType ?? (m.business_type as string | undefined)),
    target_audience: str(
      businessInfo.targetAudience ?? (m.target_audience as string | undefined),
    ),
    goal: VALID_GOALS.includes(goal) ? goal : "custom",
    offer: str(businessInfo.offer ?? (m.offer as string | undefined)),
    cta: str(businessInfo.cta ?? (m.cta as string | undefined)),
  };
}

function sanitizeSettings(raw: unknown, sections: FunnelSection[]): FunnelSettings {
  const s = isPlainObject(raw) ? raw : {};
  return {
    showNavigation: typeof s.showNavigation === "boolean"
      ? s.showNavigation
      : sections.some((sec) => sec.type === "navigation"),
    enableLeadCapture: typeof s.enableLeadCapture === "boolean"
      ? s.enableLeadCapture
      : sections.some((sec) => sec.type === "lead_form"),
  };
}

/**
 * Validates and safely corrects a raw AI response (already JSON-parsed) into
 * a `FunnelSchema`. Individually malformed pieces (an unreadable theme
 * color, a missing SEO title, an unrecognized section type) are corrected
 * with sensible fallbacks rather than failing the whole request. Only a
 * response with zero usable sections after correction - the one thing that
 * cannot be safely defaulted - throws `INVALID_AI_RESPONSE`.
 */
export function validateFunnelResponse(
  raw: unknown,
  opts: {
    fallbackName: string;
    fallbackType: string;
    businessInfo: FunnelBusinessInfo;
    prompt: string;
  },
): FunnelSchema {
  if (!isPlainObject(raw)) {
    throw new ProviderError(
      "The AI response could not be understood. Please try again.",
      "INVALID_AI_RESPONSE",
    );
  }

  const name = str(raw.name, opts.fallbackName);
  const rawType = typeof raw.type === "string" ? raw.type.toLowerCase() : "";
  const type = VALID_FUNNEL_TYPES.includes(rawType) ? rawType : opts.fallbackType;

  const rawSections = Array.isArray(raw.sections) ? raw.sections : [];
  const sections = rawSections
    .map((s, i) => sanitizeSection(s, i))
    .filter((s): s is FunnelSection => s !== null);

  if (sections.length === 0) {
    throw new ProviderError(
      "The AI did not return any usable sections for your funnel. Please try again.",
      "INVALID_AI_RESPONSE",
    );
  }

  const seo = sanitizeSeo(raw.seo, name, opts.prompt.slice(0, 160));

  return {
    version: 1,
    name,
    type,
    metadata: sanitizeMetadata(raw.metadata, opts.businessInfo),
    theme: sanitizeTheme(raw.theme),
    sections,
    seo,
    settings: sanitizeSettings(raw.settings, sections),
  };
}
