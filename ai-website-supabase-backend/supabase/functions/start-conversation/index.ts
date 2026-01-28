import { createClient } from '@supabase/supabase-js';
import { v4 as uuidv4 } from 'uuid';
import { Request, Response } from 'express';
import { supabaseAdmin } from '../../../db/supabaseAdmin';

export const startConversation = async (req: Request, res: Response) => {
    const { userId } = req.body;

    if (!userId) {
        return res.status(400).json({ error: 'User ID is required' });
    }

    const conversationId = uuidv4();
    const createdAt = new Date().toISOString();

    const { data, error } = await supabaseAdmin
        .from('conversations')
        .insert([
            {
                id: conversationId,
                user_id: userId,
                created_at: createdAt,
            },
        ]);

    if (error) {
        return res.status(500).json({ error: 'Failed to start conversation', details: error.message });
    }

    return res.status(201).json({ conversationId, createdAt });
};