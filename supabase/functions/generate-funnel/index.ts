// Supabase Edge Function: generate-funnel
//
// Flutter -> (this function) -> LLM provider -> validated funnel JSON -> `funnels` table -> Flutter.
//
// Security model mirrors generate-image/generate-music/generate-video:
//  - The caller's identity is derived ONLY from the verified JWT.
//  - A user-scoped Supabase client (anon key + forwarded Authorization
//    header) is used for reading `generations` and for writing `funnels`,
//    so Row Level Security applies exactly as if Flutter called Supabase
//    directly - this function cannot insert a funnel for anyone but the
//    authenticated caller, and RLS's `with check (auth.uid() = user_id)`
//    enforces that even if a bug tried to.
//  - A service-role client is used ONLY for `subscriptions`/
//    `credit_transactions` (client-unwritable by design).
//  - Unlike generate-image/generate-music/generate-video, this function DOES
//    write to a table (`funnels`) - but never to `generations` itself. The
//    single-writer principle is specifically about `generations`; `funnels`
//    is a new, dedicated table whose whole reason to exist is to hold the
//    validated structured document this function produces, exactly as the
//    brief's "AI generation flow" describes ("validate JSON -> store funnel
//    -> return safe result"). See docs/funnel-generation.md.
//
// Deploy with: supabase functions deploy generate-funnel
// Configure with: supabase secrets set FUNNEL_GENERATION_PROVIDER=mock (or "openai" + FUNNEL_GENERATION_API_KEY)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveProvider } from "./providers/index.ts";
import { validateFunnelResponse, VALID_FUNNEL_TYPES, VALID_GOALS } from "./schema.ts";
import { ProviderError } from "./types.ts";
import type { FunnelBusinessInfo, GenerateFunnelRequestBody } from "./types.ts";

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

const MAX_PROMPT_LENGTH = 2000;
const STORAGE_BUCKET = "app-storage";
// A funnel is one text-JSON round trip (no polling, no image/audio/video
// bytes), so a duplicate-request window similar to music's is appropriate.
const DUPLICATE_WINDOW_SECONDS = 60;
// Structured multi-section content is the most complex text-only output so
// far - priced between music (3) and video (5), a placeholder like every
// other type's cost until a real per-provider cost model is needed.
const FUNNEL_CREDIT_COST = 4;

function errorStatusFor(code: string): number {
  switch (code) {
    case "UNAUTHORIZED":
      return 401;
    case "INSUFFICIENT_CREDITS":
      return 402;
    case "INVALID_PROMPT":
    case "INVALID_REQUEST":
    case "INVALID_AI_RESPONSE":
      return 400;
    case "FORBIDDEN":
      return 403;
    case "RATE_LIMITED":
      return 429;
    case "CONFIGURATION_ERROR":
      return 500;
    default:
      return 502;
  }
}

async function resolveSignedUrl(
  client: ReturnType<typeof createClient>,
  path: string | null | undefined,
): Promise<string | null> {
  if (!path) return null;
  const { data, error } = await client.storage
    .from(STORAGE_BUCKET)
    .createSignedUrl(path, 60 * 60);
  if (error || !data) return null;
  return data.signedUrl;
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
      { success: false, error: "You must be signed in to generate a funnel.", code: "UNAUTHORIZED" },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
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

  let body: GenerateFunnelRequestBody;
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
      {
        success: false,
        error: "Please describe the funnel you want to create.",
        code: "INVALID_PROMPT",
      },
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

  const generationId = (body.generationId ?? "").toString().trim();
  if (!generationId) {
    return jsonResponse(
      { success: false, error: "Missing generationId.", code: "INVALID_REQUEST" },
      400,
    );
  }

  const funnelType = VALID_FUNNEL_TYPES.includes((body.funnelType ?? "").toLowerCase())
    ? (body.funnelType as string).toLowerCase()
    : "custom";

  const rawBusinessInfo = body.businessInfo ?? {};
  const businessInfo: FunnelBusinessInfo = {
    businessName: (rawBusinessInfo.businessName ?? "").toString().trim() || undefined,
    businessType: (rawBusinessInfo.businessType ?? "").toString().trim() || undefined,
    product: (rawBusinessInfo.product ?? "").toString().trim() || undefined,
    targetAudience: (rawBusinessInfo.targetAudience ?? "").toString().trim() || undefined,
    goal: VALID_GOALS.includes((rawBusinessInfo.goal ?? "").toString().toLowerCase())
      ? (rawBusinessInfo.goal as string).toLowerCase()
      : "custom",
    offer: (rawBusinessInfo.offer ?? "").toString().trim() || undefined,
    cta: (rawBusinessInfo.cta ?? "").toString().trim() || undefined,
  };

  // --- Verify the generation row: exists, belongs to this caller, and is
  // actually a funnel-type generation. RLS on `generations` means this
  // select silently returns nothing for a row the caller doesn't own -
  // treated as "not found" below. A generationId alone is never treated as
  // authorization by itself. ------------------------------------------------
  const { data: generation, error: genFetchError } = await userClient
    .from("generations")
    .select("id, user_id, project_id, generation_type")
    .eq("id", generationId)
    .maybeSingle();
  if (genFetchError || !generation || generation.generation_type !== "funnel") {
    return jsonResponse(
      { success: false, error: "This generation could not be found.", code: "FORBIDDEN" },
      403,
    );
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  // --- Duplicate-request protection --------------------------------------
  const { data: recentGenerations } = await userClient
    .from("generations")
    .select("id")
    .eq("user_id", userId)
    .eq("generation_type", "funnel")
    .eq("status", "processing")
    .gte(
      "created_at",
      new Date(Date.now() - DUPLICATE_WINDOW_SECONDS * 1000).toISOString(),
    );
  if (recentGenerations && recentGenerations.length > 1) {
    return jsonResponse(
      {
        success: false,
        error: "Please wait for your current funnel to finish generating.",
        code: "RATE_LIMITED",
      },
      429,
    );
  }

  // --- Credits check -------------------------------------------------------
  const { data: subscription } = await serviceClient
    .from("subscriptions")
    .select("credits_limit, credits_used")
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();

  if (subscription) {
    const remaining = subscription.credits_limit - subscription.credits_used;
    if (remaining < FUNNEL_CREDIT_COST) {
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

  // --- Call the provider -----------------------------------------------
  let providerResult;
  try {
    const provider = resolveProvider();
    providerResult = await provider.generate({
      prompt,
      funnelType,
      businessInfo,
      hasLogo: !!body.logoPath,
      hasProductImage: !!(body.productImagePath || body.referenceImagePath),
    });
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
        error: "Something went wrong while generating your funnel. Please try again.",
        code: "UNKNOWN",
      },
      500,
    );
  }

  // --- Validate/correct the AI response into a FunnelSchema ---------------
  let schema;
  try {
    schema = validateFunnelResponse(providerResult.raw, {
      fallbackName: businessInfo.businessName
        ? `${businessInfo.businessName} Landing Page`
        : "Untitled Funnel",
      fallbackType: funnelType,
      businessInfo,
      prompt,
    });
  } catch (error) {
    if (error instanceof ProviderError) {
      return jsonResponse(
        { success: false, error: error.message, code: error.code },
        errorStatusFor(error.code),
      );
    }
    throw error;
  }

  // --- Splice in real, already-uploaded image references (never trust the
  // AI to have used a real URL - it was told not to include one at all).
  // Reuses existing Storage objects rather than duplicating file bytes. ----
  const logoUrl = await resolveSignedUrl(userClient, body.logoPath);
  const productImageUrl = await resolveSignedUrl(
    userClient,
    body.productImagePath ?? body.referenceImagePath,
  );
  if (logoUrl) {
    schema.theme.logoUrl = logoUrl;
  }
  if (productImageUrl) {
    const hero = schema.sections.find((s) => s.type === "hero");
    if (hero) {
      hero.content.image = productImageUrl;
    }
  }

  // --- Store the funnel (user-scoped client -> RLS applies) ---------------
  const { data: funnelRow, error: insertError } = await userClient
    .from("funnels")
    .insert({
      user_id: userId,
      project_id: generation.project_id,
      generation_id: generationId,
      name: schema.name,
      description: businessInfo.product ?? null,
      funnel_type: schema.type,
      status: "draft",
      schema_version: schema.version,
      content: schema,
    })
    .select()
    .single();
  if (insertError || !funnelRow) {
    console.error("Funnel insert failed", insertError);
    return jsonResponse(
      {
        success: false,
        error: "Your funnel was generated but could not be saved. Please try again.",
        code: "DATABASE_ERROR",
      },
      500,
    );
  }

  // --- Deduct credits (service role) --------------------------------------
  if (subscription) {
    await serviceClient
      .from("subscriptions")
      .update({ credits_used: subscription.credits_used + FUNNEL_CREDIT_COST })
      .eq("user_id", userId);

    await serviceClient.from("credit_transactions").insert({
      user_id: userId,
      amount: -FUNNEL_CREDIT_COST,
      transaction_type: "generation",
      description: `Funnel generation (${providerResult.providerName})`,
      reference_id: funnelRow.id,
    });
  }

  return jsonResponse({
    success: true,
    funnelId: funnelRow.id,
    funnel: schema,
    provider: providerResult.providerName,
    model: providerResult.modelName,
    metadata: {
      funnelId: funnelRow.id,
      funnelType: schema.type,
      sectionsCount: schema.sections.length,
      ...providerResult.metadata,
    },
  });
});
