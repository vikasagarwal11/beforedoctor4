import { supabase } from '../db/supabaseAdmin';
import { v4 as uuidv4 } from 'uuid';
import { Conversation, Message } from '../db/types';

export const getTranscript = async (conversationId: string): Promise<Message[]> => {
    const { data, error } = await supabase
        .from<Message>('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('timestamp', { ascending: true });

    if (error) {
        throw new Error(`Error fetching transcript: ${error.message}`);
    }

    return data || [];
};

export const createConversation = async (userId: string): Promise<Conversation> => {
    const conversationId = uuidv4();
    const { data, error } = await supabase
        .from<Conversation>('conversations')
        .insert([{ id: conversationId, user_id: userId, created_at: new Date() }])
        .single();

    if (error) {
        throw new Error(`Error creating conversation: ${error.message}`);
    }

    return data;
};

export const appendMessage = async (conversationId: string, userId: string, message: string, audioUrl?: string): Promise<Message> => {
    const { data, error } = await supabase
        .from<Message>('messages')
        .insert([{ conversation_id: conversationId, user_id: userId, content: message, audio_url: audioUrl, timestamp: new Date() }])
        .single();

    if (error) {
        throw new Error(`Error appending message: ${error.message}`);
    }

    return data;
};