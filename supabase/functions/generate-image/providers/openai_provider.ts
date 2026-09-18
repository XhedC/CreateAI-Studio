import type { ImageGenerationProvider, ImageGenerationRequest } from "./provider.ts";
import type { ProviderGenerationResult } from "../types.ts";
import { ProviderError } from "../types.ts";

const GENERATIONS_URL = "https://api.openai.com/v1/images/generations";
const EDITS_URL = "https://api.openai.com/v1/images/edits";

// gpt-image-1 only accepts these fixed sizes (no arbitrary aspect ratios) -
// see docs/image-generation.md for the mapping rationale and the note to
// re-verify this against OpenAI's current API reference before relying on
// it in production.
const SIZE_BY_ASPECT_RATIO: Record<string, string> = {
  "1:1": "1024x1024",
  "16:9": "1536x1024",
  "9:16": "1024x1536",
  "4:3": "1024x1024", // no native 4:3 size; falls back to square (documented)
};

const QUALITY_MAP: Record<string, string> = {
  standard: "medium",
  high: "high",
};

const STYLE_PROMPT_PREFIX: Record<string, string> = {
  none: "",
  realistic: "A photorealistic image of ",
  cinematic: "A cinematic, dramatically lit shot of ",
  illustration: "A digital illustration of ",
  "3d": "A 3D rendered image of ",
  anime: "An anime-style illustration of ",
  minimalist: "A minimalist, clean-design image of ",
};

/**
 * Real AI vendor integration - OpenAI's Images API. Implemented against the
 * publicly documented `gpt-image-1` model as of this writing. Because vendor
 * APIs change, both the model name and provider selection are configurable
 * via Supabase Edge Function secrets (AI_IMAGE_MODEL, AI_IMAGE_PROVIDER)
 * rather than hard-coded, and this implementation should be re-verified
 * against https://platform.openai.com/docs/api-reference/images before
 * relying on it in production - see docs/image-generation.md.
 *
 * Known gaps (documented rather than silently pretended to work):
 *  - `style` has no native API parameter for gpt-image-1; it is folded into
 *    the prompt text instead of sent as a real field.
 *  - `4:3` has no native size on gpt-image-1; it falls back to 1024x1024.
 *  - The reference-image (image-to-image) path uses the /v1/images/edits
 *    endpoint, which is a different (multipart) contract than text-to-image
 *    generation and does not accept `quality`.
 */
export class OpenAiImageProvider implements ImageGenerationProvider {
  readonly name = "openai";

  constructor(
    private readonly apiKey: string,
    private readonly model: string,
  ) {}

  async generate(
    request: ImageGenerationRequest,
  ): Promise<ProviderGenerationResult> {
    const size = SIZE_BY_ASPECT_RATIO[request.settings.aspectRatio] ??
      "1024x1024";
    const quality = QUALITY_MAP[request.settings.quality] ?? "auto";
    const stylePrefix = STYLE_PROMPT_PREFIX[request.settings.style] ?? "";
    const prompt = `${stylePrefix}${request.prompt}`.trim();
    const n = Math.max(1, Math.min(4, request.settings.numberOfImages));

    const response = request.referenceImage
      ? await this.callEditsEndpoint(prompt, size, n, request.referenceImage)
      : await this.callGenerationsEndpoint(prompt, size, quality, n);

    if (!response.ok) {
      const detail = await this.safeErrorMessage(response);
      if (response.status === 429) {
        throw new ProviderError(
          "The AI image provider is rate-limited. Please try again shortly.",
          "RATE_LIMITED",
        );
      }
      throw new ProviderError(
        `The AI image provider returned an error: ${detail}`,
        "PROVIDER_ERROR",
      );
    }

    const data = await response.json();
    const items: Array<{ b64_json?: string; url?: string }> = data?.data ?? [];
    if (items.length === 0) {
      throw new ProviderError(
        "The AI image provider did not return any images.",
        "PROVIDER_ERROR",
      );
    }

    const images = await Promise.all(
      items.map(async (item) => {
        if (item.b64_json) {
          return {
            bytes: base64ToBytes(item.b64_json),
            mimeType: "image/png",
          };
        }
        if (item.url) {
          const imageResponse = await fetch(item.url);
          return {
            bytes: new Uint8Array(await imageResponse.arrayBuffer()),
            mimeType: imageResponse.headers.get("content-type") ??
              "image/png",
          };
        }
        throw new ProviderError(
          "The AI image provider response did not include image data.",
          "PROVIDER_ERROR",
        );
      }),
    );

    return {
      images,
      providerName: this.name,
      modelName: this.model,
      metadata: {
        requestedPrompt: prompt,
        mappedSize: size,
        mappedQuality: request.referenceImage ? undefined : quality,
        usedReferenceImage: Boolean(request.referenceImage),
      },
    };
  }

  private callGenerationsEndpoint(
    prompt: string,
    size: string,
    quality: string,
    n: number,
  ) {
    return fetch(GENERATIONS_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: this.model,
        prompt,
        size,
        quality,
        n,
      }),
    });
  }

  private callEditsEndpoint(
    prompt: string,
    size: string,
    n: number,
    referenceImage: { bytes: Uint8Array; mimeType: string },
  ) {
    const form = new FormData();
    form.set("model", this.model);
    form.set("prompt", prompt);
    form.set("size", size);
    form.set("n", String(n));
    form.set(
      "image",
      new Blob([referenceImage.bytes], { type: referenceImage.mimeType }),
      "reference.png",
    );

    return fetch(EDITS_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${this.apiKey}` },
      body: form,
    });
  }

  private async safeErrorMessage(response: Response): Promise<string> {
    try {
      const body = await response.json();
      // Never forward the raw provider payload verbatim to the client -
      // just the message text, which OpenAI's error shape does not use to
      // embed secrets.
      return typeof body?.error?.message === "string"
        ? body.error.message
        : `HTTP ${response.status}`;
    } catch {
      return `HTTP ${response.status}`;
    }
  }
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
