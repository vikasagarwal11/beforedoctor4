import { createClient } from '@supabase/supabase-js';
import { config } from '../config/env';

const supabaseUrl = config.SUPABASE_URL;
const supabaseKey = config.SUPABASE_SERVICE_ROLE_KEY;

const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

export default supabaseAdmin;