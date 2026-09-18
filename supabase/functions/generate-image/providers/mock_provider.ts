import type { ImageGenerationProvider, ImageGenerationRequest } from "./provider.ts";
import type { ProviderGenerationResult } from "../types.ts";
import { ProviderError } from "../types.ts";

const DIMENSIONS: Record<string, { width: number; height: number }> = {
  "1:1": { width: 1024, height: 1024 },
  "16:9": { width: 1344, height: 768 },
  "9:16": { width: 768, height: 1344 },
  "4:3": { width: 1024, height: 768 },
};

const COLORS = ["6750F4", "E91E8C", "FF9800", "2196F3", "00BFA5"];

/**
 * Development-mode stand-in used whenever AI_IMAGE_PROVIDER is unset or
 * explicitly "mock". No paid API is called. It still exercises the full
 * pipeline (fetch bytes -> upload to Storage -> update DB) so the
 * architecture can be verified end to end before real credentials exist.
 *
 * Never used unless AI_IMAGE_PROVIDER=mock (or is absent) - see
 * providers/index.ts.
 */
export class MockImageProvider implements ImageGenerationProvider {
  readonly name = "mock";

  async generate(
    request: ImageGenerationRequest,
  ): Promise<ProviderGenerationResult> {
    const { width, height } = DIMENSIONS[request.settings.aspectRatio] ??
      DIMENSIONS["1:1"];
    const count = Math.max(1, Math.min(4, request.settings.numberOfImages));

    const images = await Promise.all(
      Array.from({ length: count }, async (_, index) => {
        const color = COLORS[index % COLORS.length];
        const label = encodeURIComponent(
          `Mock ${request.settings.style}\n${request.prompt.slice(0, 40)}`,
        );
        const url =
          `https://placehold.co/${width}x${height}/${color}/FFFFFF/png?text=${label}`;
        const response = await fetch(url);
        if (!response.ok) {
          throw new ProviderError(
            "The development image provider is temporarily unavailable.",
            "PROVIDER_ERROR",
          );
        }
        const bytes = new Uint8Array(await response.arrayBuffer());
        return { bytes, mimeType: "image/png", width, height };
      }),
    );

    return {
      images,
      providerName: this.name,
      modelName: "mock-image-v1",
      metadata: {
        mock: true,
        note:
          "Placeholder output from the development provider - no paid AI API was called.",
      },
    };
  }
}
