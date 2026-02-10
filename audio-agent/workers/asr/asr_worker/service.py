from __future__ import annotations

import base64
import io
from dataclasses import dataclass

import numpy as np
import soundfile as sf
from transformers import pipeline


@dataclass(frozen=True)
class AsrConfig:
    model_id: str = "openai/whisper-large-v3"
    device: str | int = "cpu"  # set to 0 for CUDA:0
    torch_dtype: str | None = None


class AsrService:
    def __init__(self, cfg: AsrConfig):
        # HF pipeline is synchronous; we'll call it from a thread in the API layer.
        self._pipe = pipeline(
            task="automatic-speech-recognition",
            model=cfg.model_id,
            device=cfg.device,
        )

    def transcribe_wav_b64(self, audio_b64: str) -> str:
        wav_bytes = base64.b64decode(audio_b64)
        audio, sr = self._decode_audio(wav_bytes)
        out = self._pipe({"array": audio, "sampling_rate": sr},
                         chunk_length_s=30, ignore_warning=True)
        text = out.get("text", "") if isinstance(out, dict) else str(out)
        return text.strip()

    @staticmethod
    def _decode_audio(wav_bytes: bytes) -> tuple[np.ndarray, int]:
        with sf.SoundFile(io.BytesIO(wav_bytes)) as f:
            sr = int(f.samplerate)
            audio = f.read(dtype="float32")

        # Convert stereo -> mono if needed.
        if audio.ndim == 2:
            audio = np.mean(audio, axis=1)

        return audio, sr
