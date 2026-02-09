export const Models = {
  asr: {
    modelId: "openai/whisper-large-v3"
  },
  llm: {
    // Served via vLLM or TGI (not loaded in-process)
    modelId: "meta-llama/Meta-Llama-3-8B-Instruct"
  },
  tts: {
    modelId: "coqui/XTTS-v2"
  }
} as const;
