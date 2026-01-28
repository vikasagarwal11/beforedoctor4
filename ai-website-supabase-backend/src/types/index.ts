export type User = {
    id: string; // UUID
    created_at: Date;
    updated_at: Date;
    email: string;
    username: string;
};

export type Conversation = {
    id: string; // UUID
    user_id: string; // Foreign key to User
    created_at: Date;
    updated_at: Date;
};

export type Message = {
    id: string; // UUID
    conversation_id: string; // Foreign key to Conversation
    user_id: string; // Foreign key to User
    content: string; // Text content of the message
    audio_url?: string; // Optional URL for audio file
    created_at: Date;
    speaker: 'user' | 'assistant'; // Indicates if the message is from the user or AI
};

export type VoiceInput = {
    id: string; // UUID
    message_id: string; // Foreign key to Message
    audio_url: string; // URL for the audio file
    created_at: Date;
};

export type AIResponse = {
    id: string; // UUID
    message_id: string; // Foreign key to Message
    content: string; // Text content of the AI response
    audio_url?: string; // Optional URL for audio file
    created_at: Date;
};

export type AudioFile = {
    id: string; // UUID
    user_id: string; // Foreign key to User
    file_url: string; // URL for the audio file in Supabase Storage
    created_at: Date;
};