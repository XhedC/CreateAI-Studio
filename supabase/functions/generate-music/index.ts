// Supabase Edge Function: generate-music
//
// Flutter -> (this function) -> AI music provider -> Supabase Storage -> Flutter.
// Mirrors supabase/functions/generate-image/index.ts's security model and
// design decisions exactly - see that file's comments, and
// docs/music-generation.md, for the full rationale. Differences from
// generate-image are called out below.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveProvider } from './providers/index.ts';
import { ProviderError } from './types.ts';
import type { GenerateMusicRequestBody, MusicSettings } from './types.ts';

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

const DEFAULT_SETTINGS: MusicSettings = {
  genre: 'none',
  mood: 'none',
  vocalType: 'instrumental',
  language: 'English',
  duration: 'medium',
  tempo: 'none',
  instrumental: true,
};

const MAX_PROMPT_LENGTH = 2000;
const MAX_LYRICS_LENGTH = 5000;
const STORAGE_BUCKET = 'app-storage';
// Music generation runs noticeably longer than image generation (a real
// provider call can take tens of seconds), so the duplicate-request window
// is wider than generate-image's 15s to avoid false positives while one
// legitimate generation is still in flight.
const DUPLICATE_WINDOW_SECONDS = 90;
// Music costs more credits than a single image, per the brief - flat for
// now; a future phase can scale this by duration/provider instead.
const MUSIC_CREDIT_COST = 3;

const VALID_VOCAL_TYPES = ['male', 'female', 'instrumental'];
const VALID_DURATIONS = ['short', 'medium', 'long'];

function errorStatusFor(code: string): number {
  switch (code) {
    case 'UNAUTHORIZED':
      return 401;
    case 'INSUFFICIENT_CREDITS':
      return 402;
    case 'INVALID_PROMPT':
    case 'INVALID_LYRICS':
    case 'INVALID_REQUEST':
    case 'UNSUPPORTED_FORMAT':
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

function extensionFor(mimeType: string): string {
  if (mimeType.includes('mpeg') || mimeType.includes('mp3')) return 'mp3';
  if (mimeType.includes('wav')) return 'wav';
  if (mimeType.includes('mp4') || mimeType.includes('m4a')) return 'm4a';
  return 'mp3';
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
      { success: false, error: 'You must be signed in to generate music.', code: 'UNAUTHORIZED' },
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

  // Identity derived only from the verified JWT - never from the request
  // body. Storage/DB reads below use this client so RLS applies exactly as
  // it would to a direct Flutter call.
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
  const userId = userData.user.id;

  let body: GenerateMusicRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(
      { success: false, error: 'Invalid request.', code: 'INVALID_REQUEST' },
      400,
    );
  }

  const prompt = (body.prompt ?? '').toString().trim();
  if (!prompt) {
    return jsonResponse(
      { success: false, error: 'Please describe the music you want to create.', code: 'INVALID_PROMPT' },
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

  const lyrics = body.lyrics?.toString().trim() || null;
  if (lyrics && lyrics.length > MAX_LYRICS_LENGTH) {
    return jsonResponse(
      {
        success: false,
        error: `Lyrics are too long (max ${MAX_LYRICS_LENGTH} characters).`,
        code: 'INVALID_LYRICS',
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
  const settings: MusicSettings = {
    genre: typeof rawSettings.genre === 'string' ? rawSettings.genre : DEFAULT_SETTINGS.genre,
    mood: typeof rawSettings.mood === 'string' ? rawSettings.mood : DEFAULT_SETTINGS.mood,
    vocalType: VALID_VOCAL_TYPES.includes(rawSettings.vocalType ?? '')
      ? (rawSettings.vocalType as MusicSettings['vocalType'])
      : DEFAULT_SETTINGS.vocalType,
    language: typeof rawSettings.language === 'string' ? rawSettings.language : DEFAULT_SETTINGS.language,
    duration: VALID_DURATIONS.includes(rawSettings.duration ?? '')
      ? (rawSettings.duration as MusicSettings['duration'])
      : DEFAULT_SETTINGS.duration,
    tempo: typeof rawSettings.tempo === 'string' ? rawSettings.tempo : DEFAULT_SETTINGS.tempo,
    instrumental: typeof rawSettings.instrumental === 'boolean'
      ? rawSettings.instrumental
      : DEFAULT_SETTINGS.instrumental,
  };

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  // --- Verify the generation row: exists, belongs to this caller, and is
  // actually a music-type generation - see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
  const { data: generation, error: genFetchError } = await userClient
    .from('generations')
    .select('id, user_id, project_id, generation_type')
    .eq('id', generationId)
    .maybeSingle();
  if (genFetchError || !generation || generation.generation_type !== 'music') {
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
    .eq('generation_type', 'music')
    .eq('status', 'processing')
    .gte(
      'created_at',
      new Date(Date.now() - DUPLICATE_WINDOW_SECONDS * 1000).toISOString(),
    );
  if (recentGenerations && recentGenerations.length > 1) {
    return jsonResponse(
      {
        success: false,
        error: 'Please wait for your current music generation to finish.',
        code: 'RATE_LIMITED',
      },
      429,
    );
  }

  // --- Determine the server-trusted cost and reserve credits BEFORE
  // calling the provider - see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md. -----
  const { data: costRow } = await serviceClient
    .from('credit_costs')
    .select('cost')
    .eq('generation_type', 'music')
    .is('variant', null)
    .eq('active', true)
    .maybeSingle();
  const cost = costRow?.cost ?? MUSIC_CREDIT_COST;

  const { data: reservation, error: reserveError } = await serviceClient.rpc('reserve_credits', {
    p_user_id: userId,
    p_amount: cost,
    p_idempotency_key: generationId,
    p_generation_id: generationId,
    p_generation_type: 'music',
    p_project_id: generation.project_id,
    p_provider: null,
    p_description: 'Music generation',
    p_metadata: { genre: settings.genre, mood: settings.mood, duration: settings.duration },
  });
  if (reserveError || !reservation?.success) {
    const code = reservation?.code ?? 'UNKNOWN';
    return jsonResponse(
      { success: false, error: reservation?.error ?? 'Something went wrong while checking your credits.', code },
      errorStatusFor(code),
    );
  }

  async function refundReservation(reason: string) {
    await serviceClient.rpc('refund_generation_credits', {
      p_user_id: userId,
      p_amount: cost,
      p_idempotency_key: `refund:${generationId}`,
      p_generation_id: generationId,
      p_description: `Refund: ${reason}`,
      p_metadata: {},
    });
  }

  // --- Call the provider ---------------------------------------------------
  let result;
  try {
    const provider = resolveProvider();
    result = await provider.generate({ prompt, lyrics, settings });
  } catch (error) {
    await refundReservation('provider error');
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
        error: 'Something went wrong while generating your music. Please try again.',
        code: 'UNKNOWN',
      },
      500,
    );
  }

  // --- Upload result to Storage (user-scoped client -> RLS applies) ------
  const requestId = crypto.randomUUID();
  const fileName = `result.${extensionFor(result.audio.mimeType)}`;
  const path = `${userId}/generations/${requestId}/${fileName}`;

  const { error: uploadError } = await userClient.storage
    .from(STORAGE_BUCKET)
    .upload(path, result.audio.bytes, {
      contentType: result.audio.mimeType,
      upsert: true,
    });
  if (uploadError) {
    console.error('Storage upload failed', uploadError);
    await refundReservation('storage upload failed');
    return jsonResponse(
      {
        success: false,
        error: 'Your music was generated but could not be saved. Please try again.',
        code: 'STORAGE_ERROR',
      },
      500,
    );
  }

  const { data: signed, error: signError } = await userClient.storage
    .from(STORAGE_BUCKET)
    .createSignedUrl(path, 60 * 60);
  if (signError || !signed) {
    await refundReservation('could not create playback link');
    return jsonResponse(
      {
        success: false,
        error: 'Your music was saved but a playback link could not be created.',
        code: 'STORAGE_ERROR',
      },
      500,
    );
  }

  await serviceClient.rpc('finalize_generation_charge', {
    p_generation_id: generationId,
    p_metadata: { provider: result.providerName, model: result.modelName },
  });

  return jsonResponse({
    success: true,
    audio: {
      storagePath: path,
      signedUrl: signed.signedUrl,
      mimeType: result.audio.mimeType,
      fileSize: result.audio.bytes.byteLength,
      durationSeconds: result.audio.durationSeconds ?? null,
    },
    provider: result.providerName,
    model: result.modelName,
    metadata: {
      genre: settings.genre,
      mood: settings.mood,
      vocalType: settings.vocalType,
      language: settings.language,
      duration: settings.duration,
      tempo: settings.tempo,
      instrumental: settings.instrumental,
      lyrics,
      creditsCharged: cost,
      ...result.metadata,
    },
  });
});
