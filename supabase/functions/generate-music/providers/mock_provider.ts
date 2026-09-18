import type { MusicGenerationProvider, MusicGenerationRequest } from './provider.ts';
import type { ProviderGenerationResult } from '../types.ts';

const SAMPLE_RATE = 22050;

const DURATION_SECONDS: Record<string, number> = {
  short: 8,
  medium: 15,
  long: 25,
};

// A gentle little melody instead of a single flat tone, so the mock output
// is at least recognizable as "a tune" rather than a test-tone beep.
const MOOD_SCALE_HZ: Record<string, number[]> = {
  happy: [523.25, 587.33, 659.25, 783.99], // C5 D5 E5 G5
  energetic: [587.33, 659.25, 783.99, 880.0], // D5 E5 G5 A5
  sad: [349.23, 392.0, 415.3, 466.16], // F4 G4 Ab4 Bb4
  calm: [261.63, 329.63, 392.0, 440.0], // C4 E4 G4 A4
  peaceful: [261.63, 329.63, 392.0, 440.0],
  romantic: [293.66, 349.23, 440.0, 523.25], // D4 F4 A4 C5
  inspirational: [392.0, 440.0, 523.25, 587.33], // G4 A4 C5 D5
  epic: [220.0, 261.63, 329.63, 392.0], // A3 C4 E4 G4
};

/**
 * Development-mode stand-in used whenever MUSIC_GENERATION_PROVIDER is
 * unset or explicitly "mock". No paid API is called, and no external
 * network fetch is required - the "audio" is a small synthesized melody
 * generated in-process, so this provider works even with no internet
 * access from the Edge Function's perspective. It still exercises the full
 * pipeline (bytes -> upload to Storage -> update DB) end to end.
 */
export class MockMusicProvider implements MusicGenerationProvider {
  readonly name = 'mock';

  async generate(
    request: MusicGenerationRequest,
  ): Promise<ProviderGenerationResult> {
    const durationSeconds = DURATION_SECONDS[request.settings.duration] ?? 15;
    const scale = MOOD_SCALE_HZ[request.settings.mood] ?? MOOD_SCALE_HZ.calm;
    const bytes = synthesizeMelodyWav(durationSeconds, scale);

    return {
      audio: { bytes, mimeType: 'audio/wav', durationSeconds },
      providerName: this.name,
      modelName: 'mock-music-v1',
      metadata: {
        mock: true,
        note:
          'Synthesized placeholder melody from the development provider - no paid AI API was called.',
      },
    };
  }
}

/** Builds a simple looping arpeggio as 16-bit mono PCM WAV bytes. */
function synthesizeMelodyWav(durationSeconds: number, scaleHz: number[]): Uint8Array {
  const totalSamples = Math.floor(SAMPLE_RATE * durationSeconds);
  const noteSamples = Math.floor(SAMPLE_RATE * 0.4); // 400ms per note
  const pcm = new Int16Array(totalSamples);

  for (let i = 0; i < totalSamples; i++) {
    const noteIndex = Math.floor(i / noteSamples) % scaleHz.length;
    const freq = scaleHz[noteIndex];
    const t = i / SAMPLE_RATE;
    // Fade each note in/out slightly to avoid audible clicks.
    const withinNote = i % noteSamples;
    const envelope = Math.min(
      1,
      Math.min(withinNote, noteSamples - withinNote) / (SAMPLE_RATE * 0.02),
    );
    const sample = Math.sin(2 * Math.PI * freq * t) * envelope * 0.3;
    pcm[i] = Math.max(-32768, Math.min(32767, Math.round(sample * 32767)));
  }

  return pcmToWav(pcm, SAMPLE_RATE);
}

function pcmToWav(pcm: Int16Array, sampleRate: number): Uint8Array {
  const blockAlign = 2; // 16-bit mono
  const byteRate = sampleRate * blockAlign;
  const dataSize = pcm.length * 2;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);

  const writeString = (offset: number, value: string) => {
    for (let i = 0; i < value.length; i++) {
      view.setUint8(offset + i, value.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, 16, true); // bits per sample
  writeString(36, 'data');
  view.setUint32(40, dataSize, true);

  for (let i = 0; i < pcm.length; i++) {
    view.setInt16(44 + i * 2, pcm[i], true);
  }

  return new Uint8Array(buffer);
}
