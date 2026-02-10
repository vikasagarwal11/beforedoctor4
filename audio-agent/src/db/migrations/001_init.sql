-- Separate namespaces (schemas)
CREATE SCHEMA IF NOT EXISTS conversation;
CREATE SCHEMA IF NOT EXISTS transcript_store;

CREATE TABLE IF NOT EXISTS conversation.sessions (
  id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transcript_store.transcripts (
  id uuid PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES conversation.sessions(id) ON DELETE CASCADE,
  transcript_text text NOT NULL,
  role text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transcripts_session_id ON transcript_store.transcripts(session_id);
CREATE INDEX IF NOT EXISTS idx_transcripts_created_at ON transcript_store.transcripts(created_at);
