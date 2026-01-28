INSERT INTO users (id, created_at, updated_at, email) VALUES
  (gen_random_uuid(), NOW(), NOW(), 'testuser@example.com');

INSERT INTO conversations (id, user_id, created_at) VALUES
  (gen_random_uuid(), (SELECT id FROM users WHERE email = 'testuser@example.com'), NOW());

INSERT INTO messages (id, conversation_id, user_id, content, created_at, speaker_type) VALUES
  (gen_random_uuid(), (SELECT id FROM conversations WHERE user_id = (SELECT id FROM users WHERE email = 'testuser@example.com')), (SELECT id FROM users WHERE email = 'testuser@example.com'), 'Hello, how can I help you?', NOW(), 'user'),
  (gen_random_uuid(), (SELECT id FROM conversations WHERE user_id = (SELECT id FROM users WHERE email = 'testuser@example.com')), NULL, 'I am here to assist you with your queries.', NOW(), 'assistant');

INSERT INTO voice_inputs (id, message_id, audio_url) VALUES
  (gen_random_uuid(), (SELECT id FROM messages WHERE content = 'Hello, how can I help you?'), 'https://example.com/audio/user_message_1.mp3');

INSERT INTO ai_responses (id, message_id, audio_url) VALUES
  (gen_random_uuid(), (SELECT id FROM messages WHERE content = 'I am here to assist you with your queries.'), 'https://example.com/audio/ai_response_1.mp3');

INSERT INTO audio_files (id, url, created_at) VALUES
  (gen_random_uuid(), 'https://example.com/audio/user_message_1.mp3', NOW()),
  (gen_random_uuid(), 'https://example.com/audio/ai_response_1.mp3', NOW());