from __future__ import annotations

import base64
import io
import os
from dataclasses import dataclass

import numpy as np
import soundfile as sf
from scipy import signal as scipy_signal
from TTS.api import TTS

try:
    # PyTorch 2.6+ defaults to weights_only=True and blocks some globals.
    # Allowlist XTTS config so torch.load can deserialize the checkpoint.
    import torch
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import XttsArgs, XttsAudioConfig

    try:
        torch.serialization.add_safe_globals(
            [XttsConfig, XttsAudioConfig, XttsArgs])
    except Exception:
        # If the API isn't available or fails, continue; model load may still work
        pass

    # PyTorch 2.6+ may still reject additional globals while loading XTTS checkpoints.
    # Force weights_only=False to allow full deserialization from trusted checkpoints.
    try:
        _orig_torch_load = torch.load

        def _torch_load_allow_globals(*args, **kwargs):
            kwargs.setdefault("weights_only", False)
            return _orig_torch_load(*args, **kwargs)

        torch.load = _torch_load_allow_globals  # type: ignore[assignment]
    except Exception:
        pass
except Exception:
    # If torch/TTS imports fail here, they will surface during model load.
    pass


@dataclass(frozen=True)
class TtsConfig:
    # Coqui TTS model registry name for XTTS-v2
    # (This is the canonical runtime identifier used by the `TTS` library.)
    model_name: str = "tts_models/multilingual/multi-dataset/xtts_v2"


class TtsService:
    def __init__(self, cfg: TtsConfig):
        # Loading is expensive; keep singleton per process.
        self._tts = TTS(cfg.model_name)
        self._default_speaker = (
            os.getenv("TTS_SPEAKER") or "").strip() or None
        if not self._default_speaker:
            try:
                speakers = getattr(self._tts, "speakers", None)
                if isinstance(speakers, (list, tuple)) and speakers:
                    self._default_speaker = str(speakers[0])
            except Exception:
                self._default_speaker = None

    def synthesize_wav_b64(self, text: str) -> tuple[str, int]:
        # Log text length for debugging
        print(f"[TTS] Synthesizing text: {len(text)} characters")
        print(f"[TTS] Text preview: {text[:100]}..." if len(
            text) > 100 else f"[TTS] Full text: {text}")

        # No truncation - synthesize the full text
        # XTTS-v2 can handle long text, it just takes longer

        kwargs = {}
        if self._default_speaker:
            kwargs["speaker"] = self._default_speaker

        # Add quality settings for more natural voice
        kwargs["language_idx"] = "en"  # Explicit English for better quality
        # Use longer conditioning for quality
        kwargs["use_gpt_cond_len"] = True
        kwargs["top_k"] = 250  # Reduce randomness for consistency
        kwargs["top_p"] = 0.85  # Nucleus sampling for diversity
        kwargs["temperature"] = 0.75  # Slightly lower for clearer speech

        wav = self._tts.tts(text, **kwargs)
        if isinstance(wav, list):
            wav = np.array(wav, dtype=np.float32)
        elif not isinstance(wav, np.ndarray):
            wav = np.array(wav, dtype=np.float32)

        # Normalize audio to prevent clipping and improve quality
        max_val = np.max(np.abs(wav))
        if max_val > 0:
            wav = wav / max_val * 0.95  # Normalize to 95% of max to prevent clipping

        # XTTS-v2 outputs at 22050 Hz, but we need 24000 Hz for consistency with Flutter
        source_sr = int(getattr(self._tts.synthesizer,
                                "output_sample_rate", 22050) or 22050)
        target_sr = 24000

        # Resample if needed
        if source_sr != target_sr:
            print(
                f"[TTS] Resampling audio from {source_sr}Hz to {target_sr}Hz")
            # Calculate resampling ratio
            num_samples = int(len(wav) * target_sr / source_sr)
            wav = scipy_signal.resample(wav, num_samples)
            print(f"[TTS] Resampled: {len(wav)} samples at {target_sr}Hz")

        bio = io.BytesIO()
        sf.write(bio, wav, target_sr, format="WAV")
        audio_b64 = base64.b64encode(bio.getvalue()).decode("ascii")
        print(f"[TTS] Generated {len(audio_b64)} base64 bytes")
        return audio_b64, target_sr
