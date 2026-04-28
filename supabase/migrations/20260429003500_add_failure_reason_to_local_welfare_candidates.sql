alter table if exists public.local_welfare_candidates
  add column if not exists failure_reason text;

create index if not exists idx_local_welfare_candidates_failure_reason
  on public.local_welfare_candidates (failure_reason);

comment on column public.local_welfare_candidates.failure_reason is
  'Failure reason when crawler could not parse or fetch a local welfare source URL.';

notify pgrst, 'reload schema';
