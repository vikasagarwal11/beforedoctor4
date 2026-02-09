from __future__ import annotations

import asyncio
import os

from fastapi import FastAPI
from pydantic import BaseModel

from .service import AsrConfig, AsrService


class AsrRequest(BaseModel):
    audio_b64: str


class AsrResponse(BaseModel):
    transcript: str


def _device_from_env() -> str | int:
    # Examples:
    # - ASR_DEVICE=cpu
    # - ASR_DEVICE=0  (CUDA:0)
    v = os.getenv("ASR_DEVICE", "cpu")
    if v.isdigit():
        return int(v)
    return v


app = FastAPI(title="ASR Worker", version="0.1.0")
_service = AsrService(AsrConfig(model_id=os.getenv(
    "ASR_MODEL_ID", "openai/whisper-large-v3"), device=_device_from_env()))


@app.get("/healthz")
async def healthz():
    return {"ok": True}


@app.post("/v1/asr", response_model=AsrResponse)
async def asr(req: AsrRequest):
    transcript = await asyncio.to_thread(_service.transcribe_wav_b64, req.audio_b64)
    return AsrResponse(transcript=transcript)
