import { supabase } from '../db/supabaseAdmin';
import { Message, UserMessage, AIResponse } from '../db/types';

// Function to append a user message to the conversation
export const appendUserMessage = async (conversationId: string, userMessage: UserMessage) => {
    const { data, error } = await supabase
        .from<Message>('messages')
        .insert([
            {
                conversation_id: conversationId,
                content: userMessage.text,
                audio_url: userMessage.audioUrl || null,
                speaker: 'user',
                created_at: new Date().toISOString(),
            },
        ]);

    if (error) {
        throw new Error(`Error appending user message: ${error.message}`);
    }

    return data;
};

// Function to save an AI response to the conversation
export const saveAIResponse = async (conversationId: string, aiResponse: AIResponse) => {
    const { data, error } = await supabase
        .from<Message>('messages')
        .insert([
            {
                conversation_id: conversationId,
                content: aiResponse.text,
                audio_url: aiResponse.audioUrl || null,
                speaker: 'assistant',
                created_at: new Date().toISOString(),
            },
        ]);

    if (error) {
        throw new Error(`Error saving AI response: ${error.message}`);
    }

    return data;
};

// Function to fetch the full conversation transcript
export const fetchConversationTranscript = async (conversationId: string) => {
    const { data, error } = await supabase
        .from<Message>('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true });

    if (error) {
        throw new Error(`Error fetching conversation transcript: ${error.message}`);
    }

    return data;
};