"""Minimal mic streaming client.

- Captures PCM16LE mono at 16kHz
- Sends binary frames over WS to /v1/audio/stream
- Ends stream and prints transcript + response

Requirements (client env):
- pip install sounddevice numpy websocket-client

Usage:
- python mic_client.py ws://localhost:8089/v1/audio/stream
"""

from __future__ import annotations

import json
import sys
import threading
import time

import numpy as np
import sounddevice as sd
from websocket import WebSocketApp

SAMPLE_RATE = 16000
CHANNELS = 1
FRAME_MS = 50


def main(ws_url: str):
    frame_samples = int(SAMPLE_RATE * (FRAME_MS / 1000))

    stop_event = threading.Event()

    def on_open(ws):
        ws.send(json.dumps({"type": "start"}))

        def _capture():
            with sd.InputStream(samplerate=SAMPLE_RATE, channels=CHANNELS, dtype="int16") as stream:
                while not stop_event.is_set():
                    audio, _ = stream.read(frame_samples)
                    ws.send(audio.tobytes(), opcode=2)

        threading.Thread(target=_capture, daemon=True).start()

    def on_message(ws, message):
        try:
            msg = json.loads(message)
            if msg.get("type") == "result":
                print("\n=== Transcript ===\n", msg.get("transcript_text"))
                print("\n=== Response ===\n", msg.get("response_text"))
                stop_event.set()
                ws.close()
        except Exception:
            pass

    def on_error(ws, err):
        print("WS error:", err)
        stop_event.set()

    def on_close(ws, *_):
        stop_event.set()

    ws = WebSocketApp(ws_url, on_open=on_open, on_message=on_message,
                      on_error=on_error, on_close=on_close)

    print("Recording... press Enter to stop")
    t = threading.Thread(target=ws.run_forever, daemon=True)
    t.start()

    input()
    ws.send(json.dumps({"type": "end"}))

    while t.is_alive():
        time.sleep(0.1)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python mic_client.py ws://localhost:8089/v1/audio/stream")
        raise SystemExit(2)
    main(sys.argv[1])
