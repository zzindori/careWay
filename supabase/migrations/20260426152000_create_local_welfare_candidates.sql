create table if not exists public.local_welfare_candidates (
  id uuid primary key default gen_random_uuid(),
  source_url text not null unique,
  source_name text not null,
  source_type text,
  region text not null,
  sub_region text not null,
  area_detail text,
  title text,
  content text,
  phone text,
  payload jsonb,
  quality_warnings text[] not null default '{}',
  status text not null default 'candidate',
  promoted_service_url text,
  collected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_local_welfare_candidates_status
  on public.local_welfare_candidates (status);

create index if not exists idx_local_welfare_candidates_region
  on public.local_welfare_candidates (region, sub_region);

comment on table public.local_welfare_candidates is
  'Staging table for local welfare crawler pages before promotion to welfare_services.';
