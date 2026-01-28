import { createClient } from '@supabase/supabase-js';
import { Response } from 'express';

// Initialize Supabase client
const supabaseUrl = process.env.SUPABASE_URL!;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const supabase = createClient(supabaseUrl, supabaseKey);

// Function to save AI response
export const saveAIResponse = async (req: any, res: Response) => {
    const { conversationId, aiResponseText, audioUrl } = req.body;

    // Validate input
    if (!conversationId || !aiResponseText) {
        return res.status(400).json({ error: 'Missing required fields' });
    }

    // Insert AI response into the database
    const { data, error } = await supabase
        .from('ai_responses')
        .insert([
            {
                conversation_id: conversationId,
                response_text: aiResponseText,
                audio_url: audioUrl || null,
                created_at: new Date().toISOString(),
            },
        ]);

    if (error) {
        return res.status(500).json({ error: error.message });
    }

    return res.status(201).json({ message: 'AI response saved successfully', data });
};