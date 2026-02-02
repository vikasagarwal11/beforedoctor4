-- Supabase Schema: Conversation System
-- Run this in Supabase SQL Editor to create the tables
-- This enables chat-style conversation persistence with full history

-- ============================================
-- CONVERSATIONS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Index for faster user queries
CREATE INDEX IF NOT EXISTS idx_conversations_user_id 
    ON conversations(user_id);

-- Index for recent conversations
CREATE INDEX IF NOT EXISTS idx_conversations_updated_at 
    ON conversations(updated_at DESC);

-- ============================================
-- MESSAGES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sending', 'sent', 'error'))
);

-- Index for conversation messages (chronological order)
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at 
    ON messages(conversation_id, created_at);

-- Index for role filtering
CREATE INDEX IF NOT EXISTS idx_messages_role 
    ON messages(role);

-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Enable RLS
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to allow re-running this migration)
DROP POLICY IF EXISTS "Users can view own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can create own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can update own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can delete own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can view own messages" ON messages;
DROP POLICY IF EXISTS "Users can create messages in own conversations" ON messages;
DROP POLICY IF EXISTS "Users can update own messages" ON messages;
DROP POLICY IF EXISTS "Users can delete own messages" ON messages;

-- Conversations: Users can only access their own conversations
CREATE POLICY "Users can view own conversations" 
    ON conversations FOR SELECT 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own conversations" 
    ON conversations FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own conversations" 
    ON conversations FOR UPDATE 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own conversations" 
    ON conversations FOR DELETE 
    USING (auth.uid() = user_id);

-- Messages: Users can only access messages from their conversations
CREATE POLICY "Users can view own messages" 
    ON messages FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM conversations 
            WHERE conversations.id = messages.conversation_id 
            AND conversations.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create messages in own conversations" 
    ON messages FOR INSERT 
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM conversations 
            WHERE conversations.id = messages.conversation_id 
            AND conversations.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update own messages" 
    ON messages FOR UPDATE 
    USING (
        EXISTS (
            SELECT 1 FROM conversations 
            WHERE conversations.id = messages.conversation_id 
            AND conversations.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete own messages" 
    ON messages FOR DELETE 
    USING (
        EXISTS (
            SELECT 1 FROM conversations 
            WHERE conversations.id = messages.conversation_id 
            AND conversations.user_id = auth.uid()
        )
    );

-- ============================================
-- REALTIME PUBLICATION
-- ============================================
-- Enable real-time updates for messages (skip if already added)
DO $$
BEGIN
    -- Try to add messages table to realtime publication
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
EXCEPTION
    WHEN duplicate_object THEN
        -- Table already in publication, skip
        NULL;
END $$;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to auto-update conversation timestamp when messages are added
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations 
    SET updated_at = NOW() 
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to call the function
DROP TRIGGER IF EXISTS trigger_update_conversation_timestamp ON messages;
CREATE TRIGGER trigger_update_conversation_timestamp
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_timestamp();

-- ============================================
-- SAMPLE QUERIES (for reference)
-- ============================================

-- Get recent conversations for a user
-- SELECT * FROM conversations 
-- WHERE user_id = auth.uid() 
-- ORDER BY updated_at DESC 
-- LIMIT 10;

-- Get all messages in a conversation (chronological order)
-- SELECT * FROM messages 
-- WHERE conversation_id = '<conversation_id>' 
-- ORDER BY created_at ASC;

-- Count messages by role in a conversation
-- SELECT role, COUNT(*) 
-- FROM messages 
-- WHERE conversation_id = '<conversation_id>' 
-- GROUP BY role;

-- Get conversation with message count
-- SELECT c.*, COUNT(m.id) as message_count
-- FROM conversations c
-- LEFT JOIN messages m ON c.id = m.conversation_id
-- WHERE c.user_id = auth.uid()
-- GROUP BY c.id
-- ORDER BY c.updated_at DESC;
