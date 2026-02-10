from __future__ import annotations

import asyncio
import base64
import io
import logging
import os
import re
import time
from typing import Iterable, Tuple

import numpy as np
import soundfile as sf
from dotenv import find_dotenv, load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from scipy import signal as scipy_signal

from .service import TtsConfig, TtsService

load_dotenv(find_dotenv())

logger = logging.getLogger("tts_worker")
logging.basicConfig(level=logging.INFO,
                    format="[TTS_WORKER] %(levelname)s %(message)s")

app = FastAPI(title="TTS Worker", version="1.0.0")
_service: TtsService | None = None

_SYNTH_SEMAPHORE = asyncio.Semaphore(1)

TARGET_SAMPLE_RATE = 24000
TARGET_CHANNELS = 1
MAX_TEXT_LENGTH = 4000
MAX_TTS_CHUNK_CHARS = 500


class TtsRequest(BaseModel):
    text: str = Field(..., description="Input text to synthesize")


class TtsResponse(BaseModel):
    audio_pcm_b64: str
    sample_rate: int
    channels: int


def _get_service() -> TtsService:
    """Lazy load the TTS service on first use."""
    global _service
    if _service is None:
        _service = TtsService(
            TtsConfig(
                model_name=os.getenv(
                    "TTS_MODEL_NAME",
                    "tts_models/multilingual/multi-dataset/xtts_v2",
                )
            )
        )
    return _service


def _decode_wav_to_pcm16(wav_b64: str) -> Tuple[bytes, int, int]:
    """Decode WAV base64 to PCM16LE bytes with enforced 24kHz mono."""
    wav_bytes = base64.b64decode(wav_b64)
    audio, sr = sf.read(io.BytesIO(wav_bytes), dtype="float32")

    if audio.ndim > 1:
        audio = np.mean(audio, axis=1)

    if sr != TARGET_SAMPLE_RATE:
        num_samples = int(len(audio) * TARGET_SAMPLE_RATE / sr)
        audio = scipy_signal.resample(audio, num_samples)
        sr = TARGET_SAMPLE_RATE

    audio = np.clip(audio, -1.0, 1.0)
    pcm16 = (audio * 32767.0).astype(np.int16)
    return pcm16.tobytes(), sr, TARGET_CHANNELS


def _sanitize_tts_text(text: str) -> str:
    """Remove markdown and TTS-hostile characters while preserving meaning."""
    cleaned = text
    cleaned = re.sub(r"\*{1,3}([^*]+)\*{1,3}", r"\1", cleaned)
    cleaned = re.sub(r"[`_~]", "", cleaned)
    cleaned = re.sub(r"\s*\n+\s*", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned.strip()


def _split_text_for_tts(text: str, max_chars: int) -> Iterable[str]:
    """Split long text into sentence-aware chunks within max_chars."""
    cleaned = _sanitize_tts_text(text)
    if len(cleaned) <= max_chars:
        return [cleaned]

    sentences = re.split(r"(?<=[.!?])\s+", cleaned)
    chunks: list[str] = []
    current = ""

    for sentence in sentences:
        if not sentence:
            continue
        if len(sentence) > max_chars:
            # Hard split very long sentence.
            for i in range(0, len(sentence), max_chars):
                part = sentence[i:i + max_chars].strip()
                if part:
                    chunks.append(part)
            current = ""
            continue

        if not current:
            current = sentence
            continue

        if len(current) + 1 + len(sentence) <= max_chars:
            current = f"{current} {sentence}"
        else:
            chunks.append(current)
            current = sentence

    if current:
        chunks.append(current)

    return chunks


@app.get("/healthz")
async def healthz():
    return {"ok": True}


@app.post("/v1/tts", response_model=TtsResponse)
async def tts(req: TtsRequest):
    text = req.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="text must not be empty")
    if len(text) > MAX_TEXT_LENGTH:
        raise HTTPException(
            status_code=413, detail="text exceeds maximum length")

    async with _SYNTH_SEMAPHORE:
        service = _get_service()
        start = time.perf_counter()

        cleaned = _sanitize_tts_text(text)
        wav_b64, _ = await asyncio.to_thread(service.synthesize_wav_b64, cleaned)
        pcm_bytes, sr, channels = _decode_wav_to_pcm16(wav_b64)
        elapsed_ms = int((time.perf_counter() - start) * 1000)

        logger.info(
            "synth_complete",
            extra={
                "text_length": len(text),
                "chunks": 1,
                "duration_ms": elapsed_ms,
                "pcm_bytes": len(pcm_bytes),
                "sample_rate": sr,
            },
        )

        return TtsResponse(
            audio_pcm_b64=base64.b64encode(pcm_bytes).decode("ascii"),
            sample_rate=sr,
            channels=channels,
        )
