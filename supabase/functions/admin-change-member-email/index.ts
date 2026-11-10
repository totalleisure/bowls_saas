import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { handleEmailChange } from './handler.mjs';

Deno.serve((req) => handleEmailChange(req, createClient(
  Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } },
)));
