import type { FastifyInstance } from "fastify";
import type { AudioPipelineLike } from "../pipeline/audio.pipeline.js";
import { pcm16ToWavBuffer } from "../utils/audio.utils.js";

type ClientMessage = {
  type: string;
  payload?: Record<string, unknown>;
};

const AUDIO_CHUNK_BYTES = 9600; // ~200ms of PCM16 @ 24kHz mono

function chunkPcmBase64(audioB64: string): string[] {
  if (!audioB64) return [];
  let bytes: Buffer;
  try {
    bytes = Buffer.from(audioB64, "base64");
  } catch {
    return [audioB64];
  }

  const chunks: string[] = [];
  for (let i = 0; i < bytes.length; i += AUDIO_CHUNK_BYTES) {
    const end = Math.min(i + AUDIO_CHUNK_BYTES, bytes.length);
    chunks.push(bytes.subarray(i, end).toString("base64"));
  }
  return chunks.length > 0 ? chunks : [audioB64];
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sendEvent(connection: { socket?: { send: (data: string) => void }; send?: (data: string) => void }, type: string, payload: Record<string, unknown>, seq: number) {
  const sender = connection.socket?.send ?? connection.send;
  if (!sender) {
    return;
  }
  sender.call(connection.socket ?? connection, JSON.stringify({ type, payload, seq }));
}

function tryParseJsonMessage(data: Buffer): ClientMessage | null {
  const text = data.toString("utf8").trim();
  if (!text.startsWith("{") || !text.endsWith("}")) {
    return null;
  }
  try {
    return JSON.parse(text) as ClientMessage;
  } catch {
    return null;
  }
}

export async function registerAudioWebSocket(app: FastifyInstance, pipeline: AudioPipelineLike, sampleRate: number) {
  app.get("/v1/audio/stream", { websocket: true }, (connection) => {
    const ws = (connection as { socket?: { on: Function } }).socket ?? (connection as unknown as { on: Function; send: Function });
    let sessionId: string | undefined;
    let chunks: Buffer[] = [];
    let seq = 0;
    let inFlight = false;

    const nextSeq = () => ++seq;

    const emitReady = () =>
      sendEvent(connection, "server.session.state", { state: "ready" }, nextSeq());

    const emitThinking = () =>
      sendEvent(connection, "server.session.state", { state: "thinking" }, nextSeq());

    const emitError = (message: string) =>
      sendEvent(connection, "server.error", { message }, nextSeq());

    emitReady();

    const streamAudioChunks = async (audioB64: string) => {
      const bytes = Buffer.from(audioB64, "base64");
      for (let i = 0; i < bytes.length; i += AUDIO_CHUNK_BYTES) {
        const end = Math.min(i + AUDIO_CHUNK_BYTES, bytes.length);
        const chunkB64 = bytes.subarray(i, end).toString("base64");
        sendEvent(connection, "server.audio.out", { data: chunkB64 }, nextSeq());
        const chunkMs = Math.max(20, Math.round((end - i) / (sampleRate * 2) * 1000));
        await sleep(chunkMs);
      }
    };

    const handleClientMessage = async (msg: ClientMessage): Promise<boolean> => {
      const type = msg.type;
      const payload = (msg.payload ?? {}) as Record<string, unknown>;

      if (type === "client.hello") {
        sessionId = (payload["session_id"] as string | undefined) ?? sessionId;
        emitReady();
        return true;
      }

      if (type === "client.ping" || type === "ping") {
        sendEvent(connection, "server.pong", { ts: Date.now() }, nextSeq());
        return true;
      }

      if (type === "client.audio.chunk" || type === "client.audio.chunk.base64") {
        const b64 = payload["data"] as string | undefined;
        if (b64) {
          chunks.push(Buffer.from(b64, "base64"));
        }
        return true;
      }

      if (type === "client.audio.turnComplete") {
        if (inFlight) {
          emitError("Turn already in-flight");
          return true;
        }
        inFlight = true;
        const transcribeOnly = payload["transcribe_only"] === true;
        if (!transcribeOnly) {
          emitThinking();
        }

        const pcm = Buffer.concat(chunks);
        chunks = [];
        const wav = pcm16ToWavBuffer(pcm, sampleRate);
        if (transcribeOnly) {
          const asr = await pipeline.transcribeOnly(wav, sessionId);
          if (asr.transcript_text) {
            sendEvent(connection, "server.user.transcript.final", { text: asr.transcript_text }, nextSeq());
          }
          emitReady();
          inFlight = false;
          return true;
        }

        const result = await pipeline.handleTurn(wav, sessionId);

        if (result.transcript_text) {
          sendEvent(connection, "server.user.transcript.final", { text: result.transcript_text }, nextSeq());
        }
        if (result.response_text) {
          sendEvent(connection, "server.transcript.final", { text: result.response_text }, nextSeq());
        }

        if (result.response_audio_pcm_b64) {
          sendEvent(connection, "server.audio.stop", { reason: "new_turn" }, nextSeq());
          await streamAudioChunks(result.response_audio_pcm_b64);
        } else if (result.response_text) {
          sendEvent(connection, "server.audio.stop", { reason: "text_only" }, nextSeq());
        }

        emitReady();
        inFlight = false;
        return true;
      }

      if (type === "client.text.turn") {
        if (inFlight) {
          emitError("Turn already in-flight");
          return true;
        }
        inFlight = true;
        emitThinking();

        const text = (payload["text"] as string | undefined) ?? "";
        const result = await pipeline.handleTextTurn(text, sessionId);

        if (result.response_text) {
          sendEvent(connection, "server.transcript.final", { text: result.response_text }, nextSeq());
        }
        if (result.response_audio_pcm_b64) {
          sendEvent(connection, "server.audio.stop", { reason: "new_turn" }, nextSeq());
          await streamAudioChunks(result.response_audio_pcm_b64);
        } else if (result.response_text) {
          sendEvent(connection, "server.audio.stop", { reason: "text_only" }, nextSeq());
        }

        emitReady();
        inFlight = false;
        return true;
      }

      if (type === "client.session.stop") {
        chunks = [];
        emitReady();
        return true;
      }

      return false;
    };

    ws.on("message", async (data: unknown) => {
      try {
        if (typeof data === "string") {
          const msg = JSON.parse(data) as ClientMessage;
          const handled = await handleClientMessage(msg);
          if (!handled) {
            emitError("Unknown control message");
          }
          return;
        }

        // Buffer/Uint8Array frames: could be JSON text or raw PCM.
        if (Buffer.isBuffer(data)) {
          const parsed = tryParseJsonMessage(data);
          if (parsed) {
            const handled = await handleClientMessage(parsed);
            if (!handled) {
              emitError("Unknown control message");
            }
            return;
          }

          // Treat as raw PCM chunk
          chunks.push(data);
          return;
        }
        if (data instanceof ArrayBuffer) {
          const buf = Buffer.from(data);
          const parsed = tryParseJsonMessage(buf);
          if (parsed) {
            const handled = await handleClientMessage(parsed);
            if (!handled) {
              emitError("Unknown control message");
            }
            return;
          }
          chunks.push(buf);
          return;
        }
        if (data instanceof Uint8Array) {
          const buf = Buffer.from(data);
          const parsed = tryParseJsonMessage(buf);
          if (parsed) {
            const handled = await handleClientMessage(parsed);
            if (!handled) {
              emitError("Unknown control message");
            }
            return;
          }
          chunks.push(buf);
          return;
        }

        emitError("Unsupported WS frame type");
      } catch (err: any) {
        emitError(err?.message ?? "WS error");
      }
    });
  });
}
