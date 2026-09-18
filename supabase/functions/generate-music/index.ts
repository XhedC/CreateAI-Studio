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
      return 400;
    case 'RATE_LIMITED':
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

  // --- Credits check (service role - subscriptions is not client-writable) ---
  const { data: subscription } = await serviceClient
    .from('subscriptions')
    .select('credits_limit, credits_used')
    .eq('user_id', userId)
    .eq('status', 'active')
    .maybeSingle();

  if (subscription) {
    const remaining = subscription.credits_limit - subscription.credits_used;
    if (remaining < MUSIC_CREDIT_COST) {
      return jsonResponse(
        {
          success: false,
          error: "You don't have enough credits for this generation.",
          code: 'INSUFFICIENT_CREDITS',
        },
        402,
      );
    }
  }

  // --- Call the provider ---------------------------------------------------
  let result;
  try {
    const provider = resolveProvider();
    result = await provider.generate({ prompt, lyrics, settings });
  } catch (error) {
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
    return jsonResponse(
      {
        success: false,
        error: 'Your music was saved but a playback link could not be created.',
        code: 'STORAGE_ERROR',
      },
      500,
    );
  }

  // --- Deduct credits (service role) --------------------------------------
  if (subscription) {
    await serviceClient
      .from('subscriptions')
      .update({ credits_used: subscription.credits_used + MUSIC_CREDIT_COST })
      .eq('user_id', userId);

    await serviceClient.from('credit_transactions').insert({
      user_id: userId,
      amount: -MUSIC_CREDIT_COST,
      transaction_type: 'generation',
      description: `Music generation (${result.providerName})`,
      reference_id: null,
    });
  }

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
      ...result.metadata,
    },
  });
});
