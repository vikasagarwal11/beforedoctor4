-- Enable Row Level Security for the conversations and messages tables
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Policy for users to select their own conversations
CREATE POLICY "Select own conversations"
ON conversations
FOR SELECT
USING (user_id = auth.uid());

-- Policy for users to insert new conversations
CREATE POLICY "Insert own conversations"
ON conversations
FOR INSERT
WITH CHECK (user_id = auth.uid());

-- Policy for users to select their own messages
CREATE POLICY "Select own messages"
ON messages
FOR SELECT
USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

-- Policy for users to insert new messages
CREATE POLICY "Insert own messages"
ON messages
FOR INSERT
WITH CHECK (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));