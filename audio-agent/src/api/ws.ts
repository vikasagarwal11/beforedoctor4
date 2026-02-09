import type { FastifyInstance } from "fastify";
import type { AudioPipelineLike } from "../pipeline/audio.pipeline.js";
import { pcm16ToWavBuffer } from "../utils/audio.utils.js";

type ControlMessage =
  | { type: "start"; session_id?: string }
  | { type: "end"; session_id?: string }
  | { type: "ping" };

export async function registerAudioWebSocket(app: FastifyInstance, pipeline: AudioPipelineLike, sampleRate: number) {
  app.get("/v1/audio/stream", { websocket: true }, (connection) => {
    let sessionId: string | undefined;
    let chunks: Buffer[] = [];

    connection.socket.on("message", async (data: unknown) => {
      try {
        if (typeof data === "string") {
          const msg = JSON.parse(data) as ControlMessage;
          if (msg.type === "start") {
            sessionId = msg.session_id;
            chunks = [];
            connection.socket.send(JSON.stringify({ type: "ack", session_id: sessionId ?? null }));
            return;
          }
          if (msg.type === "ping") {
            connection.socket.send(JSON.stringify({ type: "pong" }));
            return;
          }
          if (msg.type === "end") {
            const pcm = Buffer.concat(chunks);
            const wav = pcm16ToWavBuffer(pcm, sampleRate);
            const result = await pipeline.handleTurn(wav, sessionId ?? msg.session_id);
            connection.socket.send(JSON.stringify({ type: "result", ...result }));
            chunks = [];
            return;
          }
          connection.socket.send(JSON.stringify({ type: "error", message: "Unknown control message" }));
          return;
        }

        // Binary frames: expect PCM16LE mono @ sampleRate.
        if (Buffer.isBuffer(data)) {
          chunks.push(data);
          return;
        }
        if (data instanceof ArrayBuffer) {
          chunks.push(Buffer.from(data));
          return;
        }

        // Some ws implementations deliver Uint8Array
        if (data instanceof Uint8Array) {
          chunks.push(Buffer.from(data));
          return;
        }

        connection.socket.send(JSON.stringify({ type: "error", message: "Unsupported WS frame type" }));
        return;
      } catch (err: any) {
        connection.socket.send(JSON.stringify({ type: "error", message: err?.message ?? "WS error" }));
      }
    });
  });
}
