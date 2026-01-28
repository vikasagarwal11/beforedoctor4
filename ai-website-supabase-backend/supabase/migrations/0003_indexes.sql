CREATE INDEX idx_conversations_user_id ON conversations (user_id);
CREATE INDEX idx_messages_conversation_id ON messages (conversation_id);
CREATE INDEX idx_messages_created_at ON messages (created_at);
CREATE INDEX idx_voice_inputs_message_id ON voice_inputs (message_id);
CREATE INDEX idx_ai_responses_message_id ON ai_responses (message_id);
CREATE INDEX idx_audio_files_user_id ON audio_files (user_id);