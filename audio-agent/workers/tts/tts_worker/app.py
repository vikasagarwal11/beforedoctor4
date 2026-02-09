from __future__ import annotations

import asyncio
import os

from dotenv import find_dotenv, load_dotenv
from fastapi import FastAPI
from pydantic import BaseModel

from .service import TtsConfig, TtsService


class TtsRequest(BaseModel):
    text: str


class TtsResponse(BaseModel):
    audio_wav_b64: str
    sample_rate: int


load_dotenv(find_dotenv())

app = FastAPI(title="TTS Worker", version="0.1.0")
_service: TtsService | None = None


def _get_service() -> TtsService:
    """Lazy load the TTS service on first use."""
    global _service
    if _service is None:
        _service = TtsService(TtsConfig(model_name=os.getenv(
            "TTS_MODEL_NAME", "tts_models/multilingual/multi-dataset/xtts_v2")))
    return _service


@app.get("/healthz")
async def healthz():
    return {"ok": True}


@app.post("/v1/tts", response_model=TtsResponse)
async def tts(req: TtsRequest):
    service = _get_service()
    audio_b64, sr = await asyncio.to_thread(service.synthesize_wav_b64, req.text)
    return TtsResponse(audio_wav_b64=audio_b64, sample_rate=sr)
