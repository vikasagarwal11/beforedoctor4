export type TranscriptRow = {
  id: string;
  session_id: string;
  transcript_text: string;
  created_at: string;
  role: "user" | "assistant";
};
