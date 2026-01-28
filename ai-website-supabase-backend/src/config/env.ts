import { config } from 'dotenv';

config();

export const ENV = {
  SUPABASE_URL: process.env.SUPABASE_URL || '',
  SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY || '',
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY || '',
  PORT: process.env.PORT || 3000,
  AI_MODEL_API_URL: process.env.AI_MODEL_API_URL || '',
  AI_MODEL_API_KEY: process.env.AI_MODEL_API_KEY || '',
};