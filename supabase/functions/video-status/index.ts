// Supabase Edge Function: video-status
//
// Polled by the Flutter app (short, cheap requests on a timer - never one
// long-lived request) while a video generation's status is "processing".
// See docs/video-generation.md for the full async architecture.
//
// This function deliberately does NOT write to the `generations` table -
// same single-writer design as generate-image/generate-music. It only
// checks the provider and, once the video is ready, uploads it to Storage
// and returns the result; the Flutter poller then calls the existing
// GenerationRepository.updateGeneration() (RLS-protected, already tested)
// to persist it.
//
// Provider-job security (per the brief): a jobId alone is never treated as
// authorization. Every request must additionally supply the generationId,
// and this function verifies (a) the caller is authenticated, (b) RLS lets
// them read that specific generation row at all (proving ownership), and
// (c) the jobId supplied matches the jobId recorded on that row when the
// job was created - a caller cannot probe an arbitrary provider job id
// without already owning a generation row that references it.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveProvider } from './providers/index.ts';
import { ProviderError } from './types.ts';
import type { VideoStatusRequestBody } from './types.ts';

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

const STORAGE_BUCKET = 'app-storage';

function errorStatusFor(code: string): number {
  switch (code) {
    case 'UNAUTHORIZED':
      return 401;
    case 'INVALID_REQUEST':
    case 'FORBIDDEN':
      return 400;
    case 'JOB_NOT_FOUND':
      return 404;
    case 'CONFIGURATION_ERROR':
      return 500;
    default:
      return 502;
  }
}

function extensionFor(mimeType: string): string {
  if (mimeType.includes('webm')) return 'webm';
  return 'mp4';
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
      { success: false, error: 'You must be signed in.', code: 'UNAUTHORIZED' },
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
  // Service-role client, scoped ONLY to finalizing/refunding the credit
  // reservation `generate-video` already made - see
  // docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md. Never used for `generations` writes.
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse(
      { success: false, error: 'Your session has expired. Please sign in again.', code: 'UNAUTHORIZED' },
      401,
    );
  }
  const userId = userData.user.id;

  let body: VideoStatusRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(
      { success: false, error: 'Invalid request.', code: 'INVALID_REQUEST' },
      400,
    );
  }

  const generationId = body.generationId?.toString().trim();
  const jobId = body.jobId?.toString().trim();
  if (!generationId || !jobId) {
    return jsonResponse(
      { success: false, error: 'Missing generationId or jobId.', code: 'INVALID_REQUEST' },
      400,
    );
  }

  // RLS on `generations` (auth.uid() = user_id) means this select silently
  // returns nothing for a generation the caller doesn't own - that's
  // indistinguishable from "not found" by design, and treated as such below.
  const { data: generation, error: fetchError } = await userClient
    .from('generations')
    .select('id, user_id, generation_type, status, metadata')
    .eq('id', generationId)
    .maybeSingle();

  if (fetchError || !generation) {
    return jsonResponse(
      { success: false, error: 'This generation could not be found.', code: 'JOB_NOT_FOUND' },
      404,
    );
  }
  if (generation.generation_type !== 'video') {
    return jsonResponse(
      { success: false, error: 'This generation is not a video.', code: 'INVALID_REQUEST' },
      400,
    );
  }
  const recordedJobId = (generation.metadata as Record<string, unknown> | null)?.jobId;
  if (recordedJobId !== jobId) {
    // The jobId supplied doesn't match what was recorded for this
    // generation - refuse rather than checking an unrelated provider job.
    return jsonResponse(
      { success: false, error: 'This job could not be verified.', code: 'FORBIDDEN' },
      403,
    );
  }

  if (generation.status !== 'processing') {
    // Already resolved (completed/failed/cancelled) - nothing to check.
    return jsonResponse({ success: true, status: generation.status });
  }

  let result;
  try {
    const provider = resolveProvider();
    result = await provider.checkStatus(jobId);
  } catch (error) {
    if (error instanceof ProviderError) {
      return jsonResponse(
        { success: false, error: error.message, code: error.code },
        errorStatusFor(error.code),
      );
    }
    console.error('Unexpected provider error', error);
    return jsonResponse(
      { success: false, error: 'Something went wrong while checking your video. Please try again.', code: 'UNKNOWN' },
      500,
    );
  }

  if (result.status === 'processing') {
    return jsonResponse({ success: true, status: 'processing' });
  }
  if (result.status === 'failed') {
    // Refund the credits generate-video reserved for this job - the
    // provider has definitively reported failure, so this is not the
    // "ambiguous state" the brief says to leave charged (that's a client
    // polling timeout, handled separately - see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md).
    const { data: chargeTx } = await serviceClient
      .from('credit_transactions')
      .select('amount')
      .eq('user_id', userId)
      .eq('reference_id', generationId)
      .eq('transaction_type', 'GENERATION_CHARGE')
      .maybeSingle();
    if (chargeTx && chargeTx.amount < 0) {
      await serviceClient.rpc('refund_generation_credits', {
        p_user_id: userId,
        p_amount: -chargeTx.amount,
        p_idempotency_key: `refund:${generationId}`,
        p_generation_id: generationId,
        p_description: 'Refund: video generation failed',
        p_metadata: {},
      });
    }
    return jsonResponse({ success: true, status: 'failed', error: result.error });
  }

  // --- completed: upload to Storage (user-scoped client -> RLS applies) --
  const requestId = crypto.randomUUID();
  const videoPath = `${userId}/generations/${requestId}/result.${extensionFor(result.video.mimeType)}`;

  const { error: uploadError } = await userClient.storage
    .from(STORAGE_BUCKET)
    .upload(videoPath, result.video.bytes, {
      contentType: result.video.mimeType,
      upsert: true,
    });
  if (uploadError) {
    console.error('Storage upload failed', uploadError);
    return jsonResponse(
      { success: false, error: 'Your video was generated but could not be saved. Please try again.', code: 'STORAGE_ERROR' },
      500,
    );
  }
  const { data: signedVideo, error: signError } = await userClient.storage
    .from(STORAGE_BUCKET)
    .createSignedUrl(videoPath, 60 * 60);
  if (signError || !signedVideo) {
    return jsonResponse(
      { success: false, error: 'Your video was saved but a playback link could not be created.', code: 'STORAGE_ERROR' },
      500,
    );
  }

  let thumbnailUrl: string | null = null;
  let thumbnailPath: string | null = null;
  if (result.thumbnail) {
    thumbnailPath = `${userId}/generations/${requestId}/thumbnail.png`;
    const { error: thumbUploadError } = await userClient.storage
      .from(STORAGE_BUCKET)
      .upload(thumbnailPath, result.thumbnail.bytes, {
        contentType: result.thumbnail.mimeType,
        upsert: true,
      });
    if (!thumbUploadError) {
      const { data: signedThumb } = await userClient.storage
        .from(STORAGE_BUCKET)
        .createSignedUrl(thumbnailPath, 60 * 60);
      thumbnailUrl = signedThumb?.signedUrl ?? null;
    }
  }

  await serviceClient.rpc('finalize_generation_charge', {
    p_generation_id: generationId,
    p_metadata: { mimeType: result.video.mimeType },
  });

  return jsonResponse({
    success: true,
    status: 'completed',
    video: {
      storagePath: videoPath,
      signedUrl: signedVideo.signedUrl,
      mimeType: result.video.mimeType,
      fileSize: result.video.bytes.byteLength,
      durationSeconds: result.video.durationSeconds ?? null,
    },
    thumbnail: thumbnailUrl
      ? { storagePath: thumbnailPath, signedUrl: thumbnailUrl }
      : null,
    metadata: result.metadata,
  });
});
