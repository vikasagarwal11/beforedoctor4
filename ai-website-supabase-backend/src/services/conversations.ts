import { supabase } from '../db/supabaseAdmin';
import { v4 as uuidv4 } from 'uuid';
import { Conversation, Message } from '../db/types';

export const startConversation = async (userId: string): Promise<Conversation> => {
    const { data, error } = await supabase
        .from('conversations')
        .insert([{ id: uuidv4(), user_id: userId, created_at: new Date() }])
        .single();

    if (error) {
        throw new Error(`Error starting conversation: ${error.message}`);
    }

    return data;
};

export const appendUserMessage = async (conversationId: string, userId: string, messageText: string, audioUrl?: string): Promise<Message> => {
    const { data, error } = await supabase
        .from('messages')
        .insert([{ id: uuidv4(), conversation_id: conversationId, user_id: userId, text: messageText, audio_url: audioUrl, created_at: new Date(), speaker: 'user' }])
        .single();

    if (error) {
        throw new Error(`Error appending user message: ${error.message}`);
    }

    return data;
};

export const fetchTranscript = async (conversationId: string): Promise<Message[]> => {
    const { data, error } = await supabase
        .from('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true });

    if (error) {
        throw new Error(`Error fetching transcript: ${error.message}`);
    }

    return data;
};