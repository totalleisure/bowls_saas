alter table public.competition_types
  drop constraint competition_types_tags_allowed;

alter table public.competition_types
  add constraint competition_types_tags_allowed
  check (
    tags <@ array[
      'match',
      'league',
      'competition',
      'drive',
      'rollup',
      'event',
      'friendly',
      'cup',
      'social',
      'training',
      'meeting'
    ]::text[]
  );
