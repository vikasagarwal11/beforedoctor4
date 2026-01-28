import { createClient } from '@supabase/supabase-js';
import { supabaseAdmin } from '../../../db/supabaseAdmin';
import { Request, Response } from 'express';

export const appendUserMessage = async (req: Request, res: Response) => {
    const { conversationId, userId, messageText, audioUrl } = req.body;

    if (!conversationId || !userId || !messageText) {
        return res.status(400).json({ error: 'Missing required fields' });
    }

    try {
        const { data, error } = await supabaseAdmin
            .from('messages')
            .insert([
                {
                    conversation_id: conversationId,
                    user_id: userId,
                    message_text: messageText,
                    audio_url: audioUrl || null,
                    created_at: new Date().toISOString(),
                    speaker_type: 'user',
                },
            ]);

        if (error) {
            throw error;
        }

        return res.status(201).json({ message: 'User message appended', data });
    } catch (error) {
        console.error('Error appending user message:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
};