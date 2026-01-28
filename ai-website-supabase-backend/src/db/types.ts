export interface User {
    id: string; // UUID
    created_at: Date; // Timestamp
    email: string; // User's email
    username: string; // User's chosen username
}

export interface Conversation {
    id: string; // UUID
    user_id: string; // Foreign key to User
    created_at: Date; // Timestamp
}

export interface Message {
    id: string; // UUID
    conversation_id: string; // Foreign key to Conversation
    user_id: string; // Foreign key to User
    content: string; // Text content of the message
    audio_url?: string; // Optional URL for audio file
    created_at: Date; // Timestamp
    speaker_type: 'user' | 'assistant'; // Indicates if the message is from the user or AI
}

export interface VoiceInput {
    id: string; // UUID
    message_id: string; // Foreign key to Message
    audio_url: string; // URL for the audio file
}

export interface AIResponse {
    id: string; // UUID
    message_id: string; // Foreign key to Message
    content: string; // Text content of the AI response
    audio_url?: string; // Optional URL for audio file
}

export interface AudioFile {
    id: string; // UUID
    user_id: string; // Foreign key to User
    file_url: string; // URL for the audio file in Supabase Storage
    created_at: Date; // Timestamp
}