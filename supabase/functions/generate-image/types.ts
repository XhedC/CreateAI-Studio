// Shared request/response contracts for the generate-image Edge Function.
// Kept provider-agnostic - see providers/provider.ts for the abstraction
// every concrete AI vendor implementation fulfils.

export interface ImageSettings {
  aspectRatio: "1:1" | "16:9" | "9:16" | "4:3";
  quality: "standard" | "high";
  style:
    | "none"
    | "realistic"
    | "cinematic"
    | "illustration"
    | "3d"
    | "anime"
    | "minimalist";
  numberOfImages: number; // clamped server-side to [1, 4]
}

export interface GenerateImageRequestBody {
  generationId: string;
  prompt: string;
  referenceImagePath?: string | null;
  settings?: Partial<ImageSettings>;
}

export interface GeneratedImageFile {
  /** Raw image bytes returned by the provider, before upload. */
  bytes: Uint8Array;
  mimeType: string;
  /** Provider-reported dimensions, if known. */
  width?: number;
  height?: number;
}

export interface ProviderGenerationResult {
  images: GeneratedImageFile[];
  /** e.g. "openai", "mock" - stored in generations.provider */
  providerName: string;
  /** e.g. "gpt-image-1", "mock-image-v1" - stored in generations.model */
  modelName: string;
  /** Provider-specific extras merged into generations.metadata. */
  metadata: Record<string, unknown>;
}

export class ProviderError extends Error {
  constructor(
    message: string,
    public readonly code:
      | "INVALID_PROMPT"
      | "PROVIDER_ERROR"
      | "TIMEOUT"
      | "RATE_LIMITED"
      | "UNSUPPORTED_REFERENCE_IMAGE"
      | "CONFIGURATION_ERROR",
  ) {
    super(message);
    this.name = "ProviderError";
  }
}

export interface UploadedImage {
  storagePath: string;
  signedUrl: string;
  mimeType: string;
  fileSize: number;
}
