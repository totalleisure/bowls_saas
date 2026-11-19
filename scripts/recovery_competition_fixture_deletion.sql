-- Roll back the schema amendment only after restoring/removing detached booking history.
-- New null links cannot safely be made NOT NULL: keep the compatible nullable column.
drop trigger if exists z_preserve_competition_on_fixture_delete on public.fixtures;
drop function if exists competition_private.detach_deleted_fixture();
