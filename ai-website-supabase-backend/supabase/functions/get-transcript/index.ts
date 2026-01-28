import { createClient } from '@supabase/supabase-js';
import { Request, Response } from 'express';
import { supabaseAdmin } from '../../../db/supabaseAdmin';

export const getTranscript = async (req: Request, res: Response) => {
    const { sessionId } = req.params;

    if (!sessionId) {
        return res.status(400).json({ error: 'Session ID is required' });
    }

    try {
        const { data, error } = await supabaseAdmin
            .from('messages')
            .select(`
                id,
                user_message,
                user_audio_url,
                ai_response,
                ai_audio_url,
                created_at,
                speaker
            `)
            .eq('session_id', sessionId)
            .order('created_at', { ascending: true });

        if (error) {
            throw error;
        }

        return res.status(200).json(data);
    } catch (error) {
        console.error('Error fetching transcript:', error);
        return res.status(500).json({ error: 'Failed to fetch transcript' });
    }
};