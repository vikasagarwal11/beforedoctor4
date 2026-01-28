import express from 'express';
import { config } from './config/env';
import { createClient } from '@supabase/supabase-js';
import conversationsRouter from './services/conversations';
import messagesRouter from './services/messages';
import audioFilesRouter from './services/audioFiles';
import transcriptsRouter from './services/transcripts';

const app = express();
const port = config.PORT || 3000;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Supabase client initialization
const supabase = createClient(config.SUPABASE_URL, config.SUPABASE_ANON_KEY);

// Routes
app.use('/api/conversations', conversationsRouter(supabase));
app.use('/api/messages', messagesRouter(supabase));
app.use('/api/audio-files', audioFilesRouter(supabase));
app.use('/api/transcripts', transcriptsRouter(supabase));

// Start the server
app.listen(port, () => {
    console.log(`Server is running on http://localhost:${port}`);
});