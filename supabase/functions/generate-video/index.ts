// Supabase Edge Function: generate-video
//
// Flutter -> (this function, fast) -> AI video provider job created
//   -> (video-status Edge Function, polled) -> video downloaded -> Storage
//
// Mirrors generate-image/index.ts and generate-music/index.ts's security
// model exactly (JWT-derived identity, JWT-scoped client for Storage/
// `generations` reads, service-role client scoped only to
// subscriptions/credit_transactions, this function never writes to
// `generations` itself). The one structural difference: video generation is
// genuinely asynchronous, so this function only *starts* the job and
// returns immediately - it does not wait for the video. See
// docs/video-generation.md.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveProvider } from './providers/index.ts';
import { ProviderError } from './types.ts';
import type { GenerateVideoRequestBody, VideoSettings } from './types.ts';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const DEFAULT_SETTINGS: VideoSettings = {
  aspectRatio: '16:9',
  resolution: '720p',
  duration: 'medium',
  motion: 'medium',
  style: 'realistic',
  fps: 24,
};

const MAX_PROMPT_LENGTH = 2000;
const STORAGE_BUCKET = 'app-storage';
// Video jobs run far longer than image/music - a much wider window than
// generate-image's 15s or generate-music's 90s is needed to avoid
// false-positives against a single legitimate in-flight job.
const DUPLICATE_WINDOW_SECONDS = 180;
// Video is the most expensive generation type so far, per the brief - flat
// for now; a future phase can scale this by resolution/duration/provider.
const VIDEO_CREDIT_COST = 5;

const VALID_ASPECT_RATIOS = ['16:9', '9:16', '1:1'];
const VALID_RESOLUTIONS = ['720p', '1080p'];
const VALID_DURATIONS = ['short', 'medium', 'long'];
const VALID_MOTIONS = ['low', 'medium', 'high'];
const VALID_FPS = [24, 30];

function errorStatusFor(code: string): number {
  switch (code) {
    case 'UNAUTHORIZED':
      return 401;
    case 'INSUFFICIENT_CREDITS':
      return 402;
    case 'INVALID_PROMPT':
    case 'INVALID_REQUEST':
    case 'MISSING_REFERENCE_IMAGE':
    case 'INVALID_REFERENCE_IMAGE':
    case 'INVALID_AMOUNT':
      return 400;
    case 'FORBIDDEN':
      return 403;
    case 'RATE_LIMITED':
    case 'DUPLICATE_REQUEST':
      return 429;
    case 'CONFIGURATION_ERROR':
      return 500;
    default:
      return 502;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse(
      { success: false, error: 'Method not allowed.', code: 'METHOD_NOT_ALLOWED' },
      405,
    );
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse(
      { success: false, error: 'You must be signed in to generate videos.', code: 'UNAUTHORIZED' },
      401,
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(
      { success: false, error: 'Server misconfiguration.', code: 'CONFIGURATION_ERROR' },
      500,
    );
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse(
      { success: false, error: 'Your session has expired. Please sign in again.', code: 'UNAUTHORIZED' },
      401,
    );
  }
  const userId = userData.user.id; // Derived from the JWT - never trust the body.

  let body: GenerateVideoRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(
      { success: false, error: 'Invalid request.', code: 'INVALID_REQUEST' },
      400,
    );
  }

  const prompt = (body.prompt ?? '').toString().trim();
  const referenceImagePath = body.referenceImagePath?.toString().trim() || null;

  if (!prompt && !referenceImagePath) {
    return jsonResponse(
      {
        success: false,
        error: 'Please describe the video you want to create or upload a reference image.',
        code: 'INVALID_REQUEST',
      },
      400,
    );
  }
  if (prompt.length > MAX_PROMPT_LENGTH) {
    return jsonResponse(
      {
        success: false,
        error: `Your description is too long (max ${MAX_PROMPT_LENGTH} characters).`,
        code: 'INVALID_PROMPT',
      },
      400,
    );
  }

  const generationId = (body.generationId ?? '').toString().trim();
  if (!generationId) {
    return jsonResponse(
      { success: false, error: 'Missing generationId.', code: 'INVALID_REQUEST' },
      400,
    );
  }

  const rawSettings = body.settings ?? {};
  const settings: VideoSettings = {
    aspectRatio: VALID_ASPECT_RATIOS.includes(rawSettings.aspectRatio ?? '')
      ? (rawSettings.aspectRatio as VideoSettings['aspectRatio'])
      : DEFAULT_SETTINGS.aspectRatio,
    resolution: VALID_RESOLUTIONS.includes(rawSettings.resolution ?? '')
      ? (rawSettings.resolution as VideoSettings['resolution'])
      : DEFAULT_SETTINGS.resolution,
    duration: VALID_DURATIONS.includes(rawSettings.duration ?? '')
      ? (rawSettings.duration as VideoSettings['duration'])
      : DEFAULT_SETTINGS.duration,
    motion: VALID_MOTIONS.includes(rawSettings.motion ?? '')
      ? (rawSettings.motion as VideoSettings['motion'])
      : DEFAULT_SETTINGS.motion,
    style: typeof rawSettings.style === 'string' ? rawSettings.style : DEFAULT_SETTINGS.style,
    fps: VALID_FPS.includes(rawSettings.fps as number) ? (rawSettings.fps as 24 | 30) : DEFAULT_SETTINGS.fps,
  };

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  // --- Verify the generation row: exists, belongs to this caller, and is
  // actually a video-type generation - see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
  const { data: generation, error: genFetchError } = await userClient
    .from('generations')
    .select('id, user_id, project_id, generation_type')
    .eq('id', generationId)
    .maybeSingle();
  if (genFetchError || !generation || generation.generation_type !== 'video') {
    return jsonResponse(
      { success: false, error: 'This generation could not be found.', code: 'FORBIDDEN' },
      403,
    );
  }

  // --- Duplicate-request protection --------------------------------------
  const { data: recentGenerations } = await userClient
    .from('generations')
    .select('id')
    .eq('user_id', userId)
    .eq('generation_type', 'video')
    .eq('status', 'processing')
    .gte(
      'created_at',
      new Date(Date.now() - DUPLICATE_WINDOW_SECONDS * 1000).toISOString(),
    );
  if (recentGenerations && recentGenerations.length > 1) {
    return jsonResponse(
      {
        success: false,
        error: 'Please wait for your current video to finish generating.',
        code: 'RATE_LIMITED',
      },
      429,
    );
  }

  // --- Determine the server-trusted cost and reserve credits BEFORE
  // starting the provider job (video-status later either finalizes this
  // charge on completion or refunds it on failure - see
  // docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md). -------------------------------
  const { data: costRow } = await serviceClient
    .from('credit_costs')
    .select('cost')
    .eq('generation_type', 'video')
    .is('variant', null)
    .eq('active', true)
    .maybeSingle();
  const cost = costRow?.cost ?? VIDEO_CREDIT_COST;

  const { data: reservation, error: reserveError } = await serviceClient.rpc('reserve_credits', {
    p_user_id: userId,
    p_amount: cost,
    p_idempotency_key: generationId,
    p_generation_id: generationId,
    p_generation_type: 'video',
    p_project_id: generation.project_id,
    p_provider: null,
    p_description: 'Video generation',
    p_metadata: { aspectRatio: settings.aspectRatio, duration: settings.duration },
  });
  if (reserveError || !reservation?.success) {
    const code = reservation?.code ?? 'UNKNOWN';
    return jsonResponse(
      { success: false, error: reservation?.error ?? 'Something went wrong while checking your credits.', code },
      errorStatusFor(code),
    );
  }

  // --- Optional reference image ------------------------------------------
  let referenceImage: { bytes: Uint8Array; mimeType: string } | null = null;
  if (referenceImagePath) {
    const { data: fileBlob, error: downloadError } = await userClient.storage
      .from(STORAGE_BUCKET)
      .download(referenceImagePath);
    if (downloadError || !fileBlob) {
      await serviceClient.rpc('refund_generation_credits', {
        p_user_id: userId,
        p_amount: cost,
        p_idempotency_key: `refund:${generationId}`,
        p_generation_id: generationId,
        p_description: 'Refund: could not read reference image',
        p_metadata: {},
      });
      return jsonResponse(
        {
          success: false,
          error: 'We could not read the uploaded reference image.',
          code: 'INVALID_REFERENCE_IMAGE',
        },
        400,
      );
    }
    referenceImage = {
      bytes: new Uint8Array(await fileBlob.arrayBuffer()),
      mimeType: fileBlob.type || 'image/png',
    };
  }

  // --- Create the provider job (fast - does not wait for the video) ------
  let job;
  try {
    const provider = resolveProvider();
    job = await provider.createJob({ prompt, settings, referenceImage });
  } catch (error) {
    await serviceClient.rpc('refund_generation_credits', {
      p_user_id: userId,
      p_amount: cost,
      p_idempotency_key: `refund:${generationId}`,
      p_generation_id: generationId,
      p_description: 'Refund: provider error starting job',
      p_metadata: {},
    });
    if (error instanceof ProviderError) {
      return jsonResponse(
        { success: false, error: error.message, code: error.code },
        errorStatusFor(error.code),
      );
    }
    console.error('Unexpected provider error', error);
    return jsonResponse(
      {
        success: false,
        error: 'Something went wrong while starting your video. Please try again.',
        code: 'UNKNOWN',
      },
      500,
    );
  }

  // Credits stay reserved (charged) while the job runs - video-status
  // finalizes this charge on completion, or refunds it if the provider
  // reports the job failed. A polling timeout with no definitive provider
  // answer is deliberately left charged (an "ambiguous state", per the
  // brief) rather than auto-refunded - see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.

  return jsonResponse({
    success: true,
    status: 'processing',
    jobId: job.jobId,
    provider: job.providerName,
    model: job.modelName,
    metadata: {
      aspectRatio: settings.aspectRatio,
      resolution: settings.resolution,
      duration: settings.duration,
      motion: settings.motion,
      style: settings.style,
      fps: settings.fps,
      jobId: job.jobId,
      creditsCharged: cost,
      ...job.metadata,
    },
  });
});
