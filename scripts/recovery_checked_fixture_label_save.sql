-- Restore the previous source call sites before removing this additive RPC.
drop function if exists public.save_fixture_label_safe(uuid,text,text,text[]);
notify pgrst,'reload schema';
