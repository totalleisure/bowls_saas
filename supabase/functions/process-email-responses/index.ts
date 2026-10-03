import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleRequest } from "./handler.ts";
serve((req) => handleRequest(req, { env: Deno.env.get, createClient }));
