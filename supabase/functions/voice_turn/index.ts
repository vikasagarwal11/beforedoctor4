// Supabase Edge Function: voice_turn
//
// Acts as the single "backend" API for the Flutter app.
// - Accepts either audio (WAV base64) or text.
// - Proxies to an external AI service (audio-agent) that performs:
//   Whisper ASR -> LLM -> TTS.
// - Returns: transcript_text (when audio provided), response_text, response_audio_pcm_b64
//
// Configure env vars in Supabase:
// - AUDIO_AGENT_URL (e.g., https://your-host/v1)
//
// Note: Edge Functions are not suitable for running Whisper/LLaMA/XTTS directly.

const corsHeaders: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
};

// ngrok free tunnels may show an interstitial warning page unless this header is present.
// This breaks server-to-server fetch() calls from Edge Functions.
const upstreamHeaders: Record<string, string> = {
  "ngrok-skip-browser-warning": "true",
};

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToB64(bytes: Uint8Array): string {
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

/**
 * Split a base64 audio string into smaller chunks for streaming.
 * Prevents single large messages and enables progressive playback.
 *
 * @param audioB64 - Full audio as base64
 * @param chunkSizeBytes - Target raw bytes per chunk (≈1s audio at 24kHz)
 * @returns Array of base64 chunks
 */
function chunkBase64Audio(audioB64: string, chunkSizeBytes = 48000): string[] {
  if (!audioB64 || audioB64.length === 0) {
    return [];
  }
  // Base64 encoding: 4 chars per 3 bytes
  const chunkSizeB64 = Math.ceil((chunkSizeBytes * 4) / 3);
  const chunks: string[] = [];
  for (let i = 0; i < audioB64.length; i += chunkSizeB64) {
    chunks.push(audioB64.substring(i, i + chunkSizeB64));
  }
  return chunks.length > 0 ? chunks : [audioB64];
}

function extractWavDataPcm16(wav: Uint8Array): { pcm: Uint8Array; sampleRate?: number } {
  // Minimal WAV parser for PCM16.
  // Returns the 'data' chunk bytes (raw PCM) and sampleRate if present.
  if (wav.length < 44) throw new Error("WAV too small");

  const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength);
  const riff = view.getUint32(0, true);
  const wave = view.getUint32(8, true);
  if (riff !== 0x46464952 || wave !== 0x45564157) throw new Error("Not a WAV RIFF/WAVE");

  let offset = 12;
  let sampleRate: number | undefined;
  let audioFormat: number | undefined;
  let bitsPerSample: number | undefined;

  while (offset + 8 <= wav.length) {
    const chunkId = view.getUint32(offset, false);
    const chunkSize = view.getUint32(offset + 4, true);
    const chunkStart = offset + 8;

    // "fmt "
    if (chunkId === 0x666d7420 && chunkSize >= 16) {
      audioFormat = view.getUint16(chunkStart + 0, true);
      // const numChannels = view.getUint16(chunkStart + 2, true);
      sampleRate = view.getUint32(chunkStart + 4, true);
      bitsPerSample = view.getUint16(chunkStart + 14, true);
    }

    // "data"
    if (chunkId === 0x64617461) {
      const dataEnd = Math.min(chunkStart + chunkSize, wav.length);
      const pcm = wav.subarray(chunkStart, dataEnd);
      if (audioFormat !== undefined && audioFormat !== 1) {
        // Not PCM
        return { pcm, sampleRate };
      }
      if (bitsPerSample !== undefined && bitsPerSample !== 16) {
        return { pcm, sampleRate };
      }
      return { pcm, sampleRate };
    }

    offset = chunkStart + chunkSize + (chunkSize % 2); // word-aligned
  }

  throw new Error("WAV data chunk not found");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const audioAgentUrl = Deno.env.get("AUDIO_AGENT_URL");
    if (!audioAgentUrl) {
      return new Response(JSON.stringify({ error: "Missing AUDIO_AGENT_URL" }), {
        status: 500,
        headers: { ...corsHeaders, "content-type": "application/json" },
      });
    }

    const body = await req.json().catch(() => ({}));
    const audioWavB64 = typeof body.audio_wav_b64 === "string" ? body.audio_wav_b64 : undefined;
    const text = typeof body.text === "string" ? body.text : undefined;
    const sessionId = typeof body.session_id === "string" ? body.session_id : undefined;
    const languageCode = typeof body.language_code === "string" && body.language_code.trim()
      ? body.language_code.trim()
      : "en-US";
    const transcribeOnly = body.transcribe_only === true;

    if (!audioWavB64 && !text) {
      return new Response(JSON.stringify({ error: "Provide audio_wav_b64 or text" }), {
        status: 400,
        headers: { ...corsHeaders, "content-type": "application/json" },
      });
    }

    if (audioWavB64) {
      // Call audio-agent /v1/audio/turn (multipart)
      const wavBytes = b64ToBytes(audioWavB64);
      const fd = new FormData();
      fd.append("audio", new Blob([wavBytes], { type: "audio/wav" }), "turn.wav");
      fd.append("language_code", languageCode);

      const url = new URL(transcribeOnly ? "/v1/asr/turn" : "/v1/audio/turn", audioAgentUrl);
      if (sessionId) url.searchParams.set("session_id", sessionId);
      url.searchParams.set("language_code", languageCode);

      const resp = await fetch(url.toString(), { method: "POST", headers: upstreamHeaders, body: fd });
      if (!resp.ok) {
        const t = await resp.text().catch(() => "");
        return new Response(JSON.stringify({ error: "audio-agent failed", status: resp.status, body: t }), {
          status: 502,
          headers: { ...corsHeaders, "content-type": "application/json" },
        });
      }

      const json = await resp.json();
      const transcriptText = String(json.transcript_text ?? "");

      if (transcribeOnly) {
        return new Response(
          JSON.stringify({
            transcript_text: transcriptText,
            response_text: "",
            response_audio_pcm_b64: "",
          }),
          { headers: { ...corsHeaders, "content-type": "application/json" } },
        );
      }

      const responseText = String(json.response_text ?? "");
      const audioPcmB64 = String(json.response_audio_pcm_b64 ?? "");

      return new Response(
        JSON.stringify({ transcript_text: transcriptText, response_text: responseText, response_audio_pcm_b64: audioPcmB64 }),
        { headers: { ...corsHeaders, "content-type": "application/json" } },
      );
    }

    // Text-only turn: call audio-agent /v1/text/turn
    const url = new URL("/v1/text/turn", audioAgentUrl);
    if (sessionId) url.searchParams.set("session_id", sessionId);

    const resp = await fetch(url.toString(), {
      method: "POST",
      headers: { "content-type": "application/json", ...upstreamHeaders },
      body: JSON.stringify({ text }),
    });

    if (!resp.ok) {
      const t = await resp.text().catch(() => "");
      return new Response(JSON.stringify({ error: "audio-agent failed", status: resp.status, body: t }), {
        status: 502,
        headers: { ...corsHeaders, "content-type": "application/json" },
      });
    }

    const json = await resp.json();
    const responseText = String(json.response_text ?? "");
    const audioPcmB64 = String(json.response_audio_pcm_b64 ?? "");

    return new Response(
      JSON.stringify({ response_text: responseText, response_audio_pcm_b64: audioPcmB64 }),
      { headers: { ...corsHeaders, "content-type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  }
});
