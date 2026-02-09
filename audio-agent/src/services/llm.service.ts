import { serviceUnavailable } from "../utils/errors.js";

type ChatMessage = { role: "system" | "user" | "assistant"; content: string };

export class LlmService {
  constructor(
    private readonly provider: "openai_compat" | "tgi" | "stub",
    private readonly baseUrl: string,
    private readonly apiKey: string,
    private readonly model: string,
    private readonly temperature: number,
    private readonly maxTokens: number
  ) {}

  async chat(messages: ChatMessage[]): Promise<string> {
    if (this.provider === "stub") {
      return this.chatStub(messages);
    }
    if (this.provider === "openai_compat") {
      return await this.chatOpenAiCompat(messages);
    }
    return await this.chatTgi(messages);
  }

  private chatStub(messages: ChatMessage[]): string {
    const lastUser = [...messages].reverse().find((m) => m.role === "user")?.content?.trim() ?? "";
    if (!lastUser) return "How can I help?";
    // Keep it short and deterministic for local dev.
    return `Got it: ${lastUser}`;
  }

  private async chatOpenAiCompat(messages: ChatMessage[]): Promise<string> {
    const baseUrl = this.baseUrl.replace(/\/v1\/?$/, "");
    const res = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(this.apiKey ? { authorization: `Bearer ${this.apiKey}` } : {})
      },
      body: JSON.stringify({
        model: this.model,
        messages,
        temperature: this.temperature,
        max_tokens: this.maxTokens
      })
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw serviceUnavailable("LLM (OpenAI-compatible) failed", { status: res.status, body });
    }

    const json = (await res.json()) as any;
    const content = json?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) {
      throw serviceUnavailable("LLM returned empty response", json);
    }
    return content.trim();
  }

  private async chatTgi(messages: ChatMessage[]): Promise<string> {
    // TGI supports multiple APIs depending on version. We use a conservative prompt format.
    const prompt = messages
      .map((m) => {
        if (m.role === "system") return `System: ${m.content}`;
        if (m.role === "user") return `User: ${m.content}`;
        return `Assistant: ${m.content}`;
      })
      .join("\n");

    const res = await fetch(`${this.baseUrl}/generate`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        inputs: `${prompt}\nAssistant:`,
        parameters: {
          temperature: this.temperature,
          max_new_tokens: this.maxTokens,
          return_full_text: false
        }
      })
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw serviceUnavailable("LLM (TGI) failed", { status: res.status, body });
    }

    const json = (await res.json()) as any;
    const text = json?.generated_text;
    if (typeof text !== "string" || !text.trim()) {
      throw serviceUnavailable("TGI returned empty response", json);
    }
    return text.trim();
  }
}
