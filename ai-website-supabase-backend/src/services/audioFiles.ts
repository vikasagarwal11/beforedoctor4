import { supabase } from '../db/supabaseAdmin';

// Function to upload an audio file to Supabase Storage
export const uploadAudioFile = async (file: File, userId: string) => {
    const { data, error } = await supabase.storage
        .from('audio-files')
        .upload(`user-${userId}/${file.name}`, file);

    if (error) {
        throw new Error(`Error uploading audio file: ${error.message}`);
    }

    return data.Key; // Return the path of the uploaded file
};

// Function to get the URL of an audio file
export const getAudioFileUrl = (filePath: string) => {
    const { publicUrl } = supabase.storage.from('audio-files').getPublicUrl(filePath);
    return publicUrl;
};

// Function to delete an audio file from Supabase Storage
export const deleteAudioFile = async (filePath: string) => {
    const { error } = await supabase.storage.from('audio-files').remove([filePath]);

    if (error) {
        throw new Error(`Error deleting audio file: ${error.message}`);
    }

    return true; // Return true if deletion was successful
};