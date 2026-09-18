import type { FunnelGenerationProvider, FunnelProviderRequest } from "./provider.ts";
import type { ProviderFunnelResult } from "../types.ts";
import { ProviderError } from "../types.ts";
import { VALID_FUNNEL_TYPES, VALID_GOALS, VALID_SECTION_TYPES } from "../schema.ts";

const CHAT_COMPLETIONS_URL = "https://api.openai.com/v1/chat/completions";

const SYSTEM_PROMPT = `You are a marketing funnel/landing-page structuring assistant for an app called CreateAI Studio.
Given a business description, you must respond with ONLY a single JSON object (no markdown, no prose) matching exactly this shape:

{
  "name": string,                      // a short name for this funnel/landing page
  "type": string,                      // one of: ${VALID_FUNNEL_TYPES_PLACEHOLDER}
  "metadata": {
    "business_name": string,
    "business_type": string,
    "target_audience": string,
    "goal": string,                    // one of: ${VALID_GOALS_PLACEHOLDER}
    "offer": string,
    "cta": string
  },
  "theme": {
    "primaryColor": string,            // hex color, e.g. "#2563EB"
    "secondaryColor": string,          // hex color
    "backgroundColor": string,         // hex color, must contrast readably with textColor
    "textColor": string,               // hex color
    "fontFamily": string               // a common web font name, e.g. "Inter"
  },
  "sections": [
    {
      "id": string,
      "type": string,                  // one of: ${VALID_SECTION_TYPES_PLACEHOLDER}
      "visible": true,
      "content": { ... }               // shape depends on "type" - use clear, relevant keys (e.g. hero: headline/subheadline/cta; benefits/features/services: title + items[]; faq: title + items[] of {question,answer}; testimonials: title + items[] of {quote,author} - use "Placeholder testimonial" style content since no real testimonials exist yet; pricing: title + plans[]; contact/about: title + description)
    }
  ],
  "seo": {
    "title": string,
    "description": string,
    "ogTitle": string,
    "ogDescription": string
  }
}

Rules:
- ALWAYS include a "hero" section first, and a "footer" section last.
- Choose ONLY the sections that make sense for the stated goal - do not force every possible section into every funnel.
- Never invent a testimonial as if it were real; label placeholder testimonials clearly as placeholders in tone (e.g. generic, not naming a specific real person/company).
- Do not include image URLs - omit any "image"/"logo" field entirely; the app fills those in separately.
- Respond with ONLY the JSON object, nothing else.`;

/**
 * Real funnel-generation provider: OpenAI Chat Completions with JSON-mode
 * output (`response_format: {type: "json_object"}`), same vendor family as
 * this project's existing OpenAI image integration. Implemented against
 * OpenAI's publicly documented Chat Completions API as of the time this was
 * written - see docs/funnel-generation.md for what to verify before
 * production use (this has not been exercised against a real key).
 */
export class OpenAiFunnelProvider implements FunnelGenerationProvider {
  constructor(private readonly apiKey: string, private readonly model: string) {}

  async generate(request: FunnelProviderRequest): Promise<ProviderFunnelResult> {
    const systemPrompt = SYSTEM_PROMPT
      .replace("VALID_FUNNEL_TYPES_PLACEHOLDER", VALID_FUNNEL_TYPES.join(", "))
      .replace("VALID_GOALS_PLACEHOLDER", VALID_GOALS.join(", "))
      .replace("VALID_SECTION_TYPES_PLACEHOLDER", VALID_SECTION_TYPES.join(", "));

    const userPrompt = [
      `Business description / prompt: ${request.prompt}`,
      `Funnel type: ${request.funnelType}`,
      `Business name: ${request.businessInfo.businessName ?? "(not provided)"}`,
      `Business type: ${request.businessInfo.businessType ?? "(not provided)"}`,
      `Product/service: ${request.businessInfo.product ?? "(not provided)"}`,
      `Target audience: ${request.businessInfo.targetAudience ?? "(not provided)"}`,
      `Main goal: ${request.businessInfo.goal ?? "(not provided)"}`,
      `Offer: ${request.businessInfo.offer ?? "(not provided)"}`,
      `Call to action: ${request.businessInfo.cta ?? "(not provided)"}`,
      request.hasLogo ? "A logo image has been uploaded." : "",
      request.hasProductImage ? "A product/reference image has been uploaded." : "",
    ].filter(Boolean).join("\n");

    let response: Response;
    try {
      response = await fetch(CHAT_COMPLETIONS_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: this.model,
          response_format: { type: "json_object" },
          temperature: 0.7,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt },
          ],
        }),
      });
    } catch {
      throw new ProviderError(
        "Could not reach the AI provider. Please try again.",
        "TIMEOUT",
      );
    }

    if (response.status === 401) {
      throw new ProviderError("The AI provider rejected our credentials.", "CONFIGURATION_ERROR");
    }
    if (response.status === 429) {
      throw new ProviderError("The AI provider is rate-limiting requests. Please try again shortly.", "RATE_LIMITED");
    }
    if (!response.ok) {
      throw new ProviderError(`The AI provider returned an error (${response.status}).`, "PROVIDER_ERROR");
    }

    const body = await response.json();
    const content = body?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      throw new ProviderError("The AI provider returned an unexpected response.", "INVALID_AI_RESPONSE");
    }

    let raw: unknown;
    try {
      raw = JSON.parse(content);
    } catch {
      // Structural validation happens in schema.ts once this returns -
      // a parse failure here is reported the same way as any other
      // malformed response, not treated as a hard provider outage.
      raw = null;
    }

    return {
      raw,
      providerName: "openai",
      modelName: this.model,
      metadata: {},
    };
  }
}
