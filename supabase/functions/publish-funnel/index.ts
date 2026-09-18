// Supabase Edge Function: publish-funnel
//
// Flutter -> (this function) -> funnels row updated (published + snapshot).
// Handles both the FIRST publish and every REPUBLISH identically - a
// republish is just "publish again" on a funnel that already has a
// public_slug (which is reused, never regenerated), a fresh
// `published_content` snapshot, and an incremented `published_version`.
//
// Security model mirrors generate-funnel/index.ts:
//  - The caller's identity is derived ONLY from the verified JWT.
//  - A user-scoped Supabase client (anon key + forwarded Authorization
//    header) is used for EVERY read and write here - RLS's
//    `funnels_select_own`/`funnels_update_own` policies mean this function
//    can never read or publish a funnel it doesn't own, and a funnelId
//    alone is never treated as authorization by itself.
//  - No service-role client is used at all: the public_slug uniqueness
//    constraint is a real Postgres unique index, enforced regardless of
//    RLS, so a plain owner-scoped UPDATE is sufficient - on a collision
//    (23505) this function just retries with the next candidate slug.
//  - Publishing intentionally does NOT touch credits/subscriptions in any
//    way - see docs/PHASE_7_PUBLISHING.md "Phase 6 compatibility".
//
// Deploy with: supabase functions deploy publish-funnel
// Configure with: supabase secrets set PUBLIC_APP_URL=https://your-domain.example

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { PublishFunnelRequestBody } from "./types.ts";

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

const MAX_SLUG_ATTEMPTS = 8;
const MAX_SLUG_LENGTH = 60;
const UNIQUE_VIOLATION = "23505";
// Combining diacritical marks (U+0300-U+036F) left behind by
// `.normalize("NFKD")` - stripping them turns e.g. "café" into "cafe"
// before the non-alphanumeric pass below removes anything else foreign.
const COMBINING_MARKS = /[̀-ͯ]/g;

function errorStatusFor(code: string): number {
  switch (code) {
    case "UNAUTHORIZED":
      return 401;
    case "INVALID_REQUEST":
    case "VALIDATION_FAILED":
      return 400;
    case "FORBIDDEN":
      return 403;
    case "SLUG_UNAVAILABLE":
      return 409;
    case "CONFIGURATION_ERROR":
      return 500;
    default:
      return 502;
  }
}

/** Lowercase, URL-safe, human-readable base slug from a funnel name - see
 * docs/PHASE_7_PUBLISHING.md "Public funnel slug" for the exact rules. */
function slugify(input: string): string {
  const base = input
    .toLowerCase()
    .normalize("NFKD")
    .replace(COMBINING_MARKS, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, MAX_SLUG_LENGTH)
    .replace(/-+$/g, "");
  return base || "funnel";
}

/** Validates a funnel is actually publishable - see
 * docs/PHASE_7_PUBLISHING.md "Publish validation" for the full rule list.
 * Deliberately lightweight: `content` was already validated once by
 * FunnelSchemaValidator/validateFunnelResponse at generation time, so this
 * only checks the things that can regress via manual editing afterward. */
function validateForPublish(
  funnelName: string,
  content: Record<string, unknown>,
): string[] {
  const errors: string[] = [];

  if (!funnelName || !funnelName.trim()) {
    errors.push("Your funnel needs a name before it can be published.");
  }

  const sections = Array.isArray(content.sections) ? content.sections : [];
  const visibleSections = sections.filter(
    (s) => typeof s === "object" && s !== null && (s as Record<string, unknown>).visible !== false,
  );
  if (visibleSections.length === 0) {
    errors.push(
      "Your funnel has no visible sections - add or show at least one section before publishing.",
    );
  }

  for (const raw of sections) {
    if (typeof raw !== "object" || raw === null) continue;
    const section = raw as Record<string, unknown>;
    const type = section.type;
    const sectionContent = (section.content ?? {}) as Record<string, unknown>;

    if (type === "hero") {
      const headline = sectionContent.headline;
      if (typeof headline !== "string" || !headline.trim()) {
        errors.push("Your hero section is missing a headline.");
      }
    }
    if (type === "final_cta" || type === "appointment_cta") {
      const ctaText = sectionContent.cta ?? sectionContent.headline;
      if (typeof ctaText !== "string" || !ctaText.trim()) {
        errors.push(
          "Your funnel cannot be published because the CTA section is missing required text.",
        );
      }
    }
  }

  return errors;
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
      { success: false, error: "You must be signed in to publish a funnel.", code: "UNAUTHORIZED" },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    return jsonResponse(
      { success: false, error: "Server misconfiguration.", code: "CONFIGURATION_ERROR" },
      500,
    );
  }
  // Never hardcoded, never a fake default that looks production-real -
  // see docs/PHASE_7_PUBLISHING.md "Environment / secrets".
  const publicAppUrl = (Deno.env.get("PUBLIC_APP_URL") ?? "").replace(/\/+$/, "");

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

  let body: PublishFunnelRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(
      { success: false, error: "Invalid request.", code: "INVALID_REQUEST" },
      400,
    );
  }

  const funnelId = (body.funnelId ?? "").toString().trim();
  if (!funnelId) {
    return jsonResponse(
      { success: false, error: "Missing funnelId.", code: "INVALID_REQUEST" },
      errorStatusFor("INVALID_REQUEST"),
    );
  }

  // RLS (`funnels_select_own`) means this silently returns nothing for a
  // funnel the caller doesn't own - treated as "not found" below. A
  // funnelId alone is never treated as authorization by itself.
  const { data: funnel, error: fetchError } = await userClient
    .from("funnels")
    .select("id, name, content, public_slug, published_version")
    .eq("id", funnelId)
    .maybeSingle();

  if (fetchError || !funnel) {
    return jsonResponse(
      { success: false, error: "This funnel could not be found.", code: "FORBIDDEN" },
      errorStatusFor("FORBIDDEN"),
    );
  }

  const validationErrors = validateForPublish(
    funnel.name as string,
    (funnel.content ?? {}) as Record<string, unknown>,
  );
  if (validationErrors.length > 0) {
    return jsonResponse(
      {
        success: false,
        error: validationErrors[0],
        errors: validationErrors,
        code: "VALIDATION_FAILED",
      },
      errorStatusFor("VALIDATION_FAILED"),
    );
  }

  const existingSlug = (funnel.public_slug as string | null) ?? null;
  const baseSlug = slugify(funnel.name as string);
  const nextVersion = ((funnel.published_version as number | null) ?? 0) + 1;
  const nowIso = new Date().toISOString();

  async function attemptUpdate(slugCandidate: string) {
    return await userClient
      .from("funnels")
      .update({
        published: true,
        published_at: nowIso,
        unpublished_at: null,
        published_content: funnel.content,
        published_version: nextVersion,
        public_slug: slugCandidate,
      })
      .eq("id", funnelId)
      .select("public_slug, published_at, published_version")
      .single();
  }

  let result;
  if (existingSlug) {
    // Republish - the slug is stable once assigned, never regenerated, so
    // a previously-shared link keeps working (see
    // docs/PHASE_7_PUBLISHING.md "Publish versioning").
    const { data, error } = await attemptUpdate(existingSlug);
    if (error) {
      console.error("Unexpected error republishing funnel", error);
      return jsonResponse(
        { success: false, error: "Something went wrong while publishing your funnel. Please try again.", code: "UNKNOWN" },
        500,
      );
    }
    result = data;
  } else {
    // First publish - generate a collision-safe slug. The unique index on
    // public_slug is the actual source of truth; a 23505 here just means
    // "try the next candidate", not a real error.
    let lastError: { code?: string } | null = null;
    for (let attempt = 0; attempt < MAX_SLUG_ATTEMPTS; attempt++) {
      const candidate = attempt === 0 ? baseSlug : `${baseSlug}-${attempt + 1}`;
      const { data, error } = await attemptUpdate(candidate);
      if (!error) {
        result = data;
        break;
      }
      lastError = error;
      if (error.code !== UNIQUE_VIOLATION) {
        console.error("Unexpected error publishing funnel", error);
        return jsonResponse(
          { success: false, error: "Something went wrong while publishing your funnel. Please try again.", code: "UNKNOWN" },
          500,
        );
      }
    }
    if (!result) {
      console.error("Exhausted slug attempts", lastError);
      return jsonResponse(
        {
          success: false,
          error: "Could not generate a unique public link for this funnel. Please try again.",
          code: "SLUG_UNAVAILABLE",
        },
        errorStatusFor("SLUG_UNAVAILABLE"),
      );
    }
  }

  const slug = result.public_slug as string;
  return jsonResponse({
    success: true,
    slug,
    publicUrl: publicAppUrl ? `${publicAppUrl}/f/${slug}` : `/f/${slug}`,
    publishedAt: result.published_at,
    publishedVersion: result.published_version,
  });
});
