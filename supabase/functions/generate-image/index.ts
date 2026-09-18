// Supabase Edge Function: generate-image
//
// Flutter -> (this function) -> AI image provider -> Supabase Storage -> Flutter.
//
// Security model:
//  - The caller's identity is derived ONLY from the verified JWT
//    (`userClient.auth.getUser()`), never from anything in the request body.
//  - A "user-scoped" Supabase client (anon key + forwarded Authorization
//    header) is used for Storage and for reading `generations`, so Row
//    Level Security applies exactly as if Flutter called Supabase directly.
//  - A separate "service-role" client is used ONLY for `subscriptions` /
//    `credit_transactions` - the two tables intentionally have no
//    client-writable RLS policy (see supabase/migrations), so crediting can
//    only happen from trusted backend code.
//  - This function deliberately does NOT write to the `generations` table.
//    The Flutter app's existing GenerationOrchestrator/GenerationRepository
//    (Phase 1, unchanged) owns creating the pending row and persisting the
//    final result - a single writer avoids races between this function and
//    the client, and reuses already-tested code. See docs/image-generation.md.
//
// Deploy with: supabase functions deploy generate-image
// Configure with: supabase secrets set AI_IMAGE_PROVIDER=mock (or "openai" + AI_IMAGE_API_KEY)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveProvider } from "./providers/index.ts";
import { ProviderError } from "./types.ts";
import type { GenerateImageRequestBody, ImageSettings } from "./types.ts";

// Inlined rather than imported from a sibling function's shared folder, so
// this function's deployment bundle is fully self-contained.
const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const DEFAULT_SETTINGS: ImageSettings = {
  aspectRatio: "1:1",
  quality: "standard",
  style: "none",
  numberOfImages: 1,
};

const MAX_PROMPT_LENGTH = 2000;
const STORAGE_BUCKET = "app-storage";
const DUPLICATE_WINDOW_SECONDS = 15;
const VALID_ASPECT_RATIOS = ["1:1", "16:9", "9:16", "4:3"];
const VALID_QUALITIES = ["standard", "high"];
const VALID_STYLES = [
  "none",
  "realistic",
  "cinematic",
  "illustration",
  "3d",
  "anime",
  "minimalist",
];

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Math.floor(value)));
}

function extensionFor(mimeType: string): string {
  if (mimeType.includes("png")) return "png";
  if (mimeType.includes("webp")) return "webp";
  if (mimeType.includes("jpeg") || mimeType.includes("jpg")) return "jpg";
  return "png";
}

function errorStatusFor(code: string): number {
  switch (code) {
    case "UNAUTHORIZED":
      return 401;
    case "INSUFFICIENT_CREDITS":
      return 402;
    case "INVALID_PROMPT":
    case "INVALID_REQUEST":
    case "INVALID_REFERENCE_IMAGE":
    case "UNSUPPORTED_REFERENCE_IMAGE":
      return 400;
    case "RATE_LIMITED":
      return 429;
    case "CONFIGURATION_ERROR":
      return 500;
    default:
      return 502;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, error: "Method not allowed.", code: "METHOD_NOT_ALLOWED" },
      405,
    );
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(
      { success: false, error: "You must be signed in to generate images.", code: "UNAUTHORIZED" },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    // These three are auto-injected by the Supabase platform for every Edge
    // Function - if missing, the function isn't running on Supabase.
    return jsonResponse(
      { success: false, error: "Server misconfiguration.", code: "CONFIGURATION_ERROR" },
      500,
    );
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse(
      { success: false, error: "Your session has expired. Please sign in again.", code: "UNAUTHORIZED" },
      401,
    );
  }
  const userId = userData.user.id; // Derived from the JWT - never trust the body.

  let body: GenerateImageRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(
      { success: false, error: "Invalid request.", code: "INVALID_REQUEST" },
      400,
    );
  }

  const prompt = (body.prompt ?? "").toString().trim();
  if (!prompt) {
    return jsonResponse(
      { success: false, error: "Please enter a description for your image.", code: "INVALID_PROMPT" },
      400,
    );
  }
  if (prompt.length > MAX_PROMPT_LENGTH) {
    return jsonResponse(
      {
        success: false,
        error: `Your description is too long (max ${MAX_PROMPT_LENGTH} characters).`,
        code: "INVALID_PROMPT",
      },
      400,
    );
  }

  const rawSettings = body.settings ?? {};
  const settings: ImageSettings = {
    aspectRatio: VALID_ASPECT_RATIOS.includes(rawSettings.aspectRatio ?? "")
      ? (rawSettings.aspectRatio as ImageSettings["aspectRatio"])
      : DEFAULT_SETTINGS.aspectRatio,
    quality: VALID_QUALITIES.includes(rawSettings.quality ?? "")
      ? (rawSettings.quality as ImageSettings["quality"])
      : DEFAULT_SETTINGS.quality,
    style: VALID_STYLES.includes(rawSettings.style ?? "")
      ? (rawSettings.style as ImageSettings["style"])
      : DEFAULT_SETTINGS.style,
    numberOfImages: clamp(
      Number(rawSettings.numberOfImages ?? 1) || 1,
      1,
      4,
    ),
  };

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  // --- Duplicate-request protection --------------------------------------
  // The Flutter orchestrator already marks the new generation "processing"
  // before calling this function, so a count of 1 is the current request
  // itself - only 2+ indicates a genuine overlapping/duplicate call.
  const { data: recentGenerations } = await userClient
    .from("generations")
    .select("id")
    .eq("user_id", userId)
    .eq("generation_type", "image")
    .eq("status", "processing")
    .gte(
      "created_at",
      new Date(Date.now() - DUPLICATE_WINDOW_SECONDS * 1000).toISOString(),
    );
  if (recentGenerations && recentGenerations.length > 1) {
    return jsonResponse(
      {
        success: false,
        error: "Please wait for your current image to finish generating.",
        code: "RATE_LIMITED",
      },
      429,
    );
  }

  // --- Credits check (subscriptions is not client-writable, but IS
  // client-readable - we still use the service client here so a missing
  // row can't be worked around, and so this check can't be bypassed by a
  // future RLS change on the read policy). ------------------------------
  const { data: subscription } = await serviceClient
    .from("subscriptions")
    .select("credits_limit, credits_used")
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();

  // Development-safe default: if no subscription row exists (shouldn't
  // happen once the Phase 1 handle_new_user trigger has run, but a Phase 2
  // dev/test account might predate it), don't block generation.
  if (subscription) {
    const remaining = subscription.credits_limit - subscription.credits_used;
    if (remaining < settings.numberOfImages) {
      return jsonResponse(
        {
          success: false,
          error: "You don't have enough credits for this generation.",
          code: "INSUFFICIENT_CREDITS",
        },
        402,
      );
    }
  }

  // --- Optional reference image ------------------------------------------
  let referenceImage: { bytes: Uint8Array; mimeType: string } | null = null;
  if (body.referenceImagePath) {
    const { data: fileBlob, error: downloadError } = await userClient.storage
      .from(STORAGE_BUCKET)
      .download(body.referenceImagePath);
    if (downloadError || !fileBlob) {
      return jsonResponse(
        {
          success: false,
          error: "We could not read the uploaded reference image.",
          code: "INVALID_REFERENCE_IMAGE",
        },
        400,
      );
    }
    referenceImage = {
      bytes: new Uint8Array(await fileBlob.arrayBuffer()),
      mimeType: fileBlob.type || "image/png",
    };
  }

  // --- Call the provider ---------------------------------------------------
  let result;
  try {
    const provider = resolveProvider();
    result = await provider.generate({ prompt, settings, referenceImage });
  } catch (error) {
    if (error instanceof ProviderError) {
      return jsonResponse(
        { success: false, error: error.message, code: error.code },
        errorStatusFor(error.code),
      );
    }
    console.error("Unexpected provider error", error);
    return jsonResponse(
      {
        success: false,
        error: "Something went wrong while generating your image. Please try again.",
        code: "UNKNOWN",
      },
      500,
    );
  }

  // --- Upload results to Storage (user-scoped client -> RLS applies) -----
  const requestId = crypto.randomUUID();
  const uploaded: Array<
    { storagePath: string; signedUrl: string; mimeType: string; fileSize: number }
  > = [];

  for (let i = 0; i < result.images.length; i++) {
    const image = result.images[i];
    const fileName = `${i === 0 ? "result" : `result-${i + 1}`}.${
      extensionFor(image.mimeType)
    }`;
    const path = `${userId}/generations/${requestId}/${fileName}`;

    const { error: uploadError } = await userClient.storage
      .from(STORAGE_BUCKET)
      .upload(path, image.bytes, {
        contentType: image.mimeType,
        upsert: true,
      });
    if (uploadError) {
      console.error("Storage upload failed", uploadError);
      return jsonResponse(
        {
          success: false,
          error: "Your image was generated but could not be saved. Please try again.",
          code: "STORAGE_ERROR",
        },
        500,
      );
    }

    const { data: signed, error: signError } = await userClient.storage
      .from(STORAGE_BUCKET)
      .createSignedUrl(path, 60 * 60);
    if (signError || !signed) {
      return jsonResponse(
        {
          success: false,
          error: "Your image was saved but a preview link could not be created.",
          code: "STORAGE_ERROR",
        },
        500,
      );
    }

    uploaded.push({
      storagePath: path,
      signedUrl: signed.signedUrl,
      mimeType: image.mimeType,
      fileSize: image.bytes.byteLength,
    });
  }

  // --- Deduct credits (service role - see comment above) -----------------
  if (subscription) {
    await serviceClient
      .from("subscriptions")
      .update({ credits_used: subscription.credits_used + settings.numberOfImages })
      .eq("user_id", userId);

    await serviceClient.from("credit_transactions").insert({
      user_id: userId,
      amount: -settings.numberOfImages,
      transaction_type: "generation",
      description: `Image generation (${settings.numberOfImages} image${
        settings.numberOfImages > 1 ? "s" : ""
      }, ${result.providerName})`,
      reference_id: null,
    });
  }

  return jsonResponse({
    success: true,
    images: uploaded,
    provider: result.providerName,
    model: result.modelName,
    metadata: {
      aspectRatio: settings.aspectRatio,
      quality: settings.quality,
      style: settings.style,
      numberOfImages: settings.numberOfImages,
      ...result.metadata,
    },
  });
});
