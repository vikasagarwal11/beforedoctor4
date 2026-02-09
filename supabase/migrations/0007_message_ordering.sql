-- Add ordering metadata to messages for stable user/assistant ordering
alter table public.messages
  add column if not exists turn_index integer,
  add column if not exists message_index smallint,
  add column if not exists client_created_at timestamptz;

create index if not exists messages_conversation_turn_idx
  on public.messages (conversation_id, turn_index, message_index, created_at);
