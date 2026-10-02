-- Stride — paste this into the SQL Editor of Stride's own Supabase project and hit Run.
--
-- stride_docs    one row per person: runs, check-ins, zones, plan state.
-- stride_samples one row per run: the second-by-second traces behind the charts.

create table if not exists public.stride_docs (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  data       jsonb       not null,
  version    bigint      not null default 1,
  updated_at timestamptz not null default now(),
  constraint stride_docs_size check (pg_column_size(data) < 5000000)
);

create table if not exists public.stride_samples (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  run_id     text        not null,
  data       jsonb       not null,
  created_at timestamptz not null default now(),
  primary key (user_id, run_id),
  constraint stride_samples_size check (pg_column_size(data) < 2000000)
);

alter table public.stride_docs    enable row level security;
alter table public.stride_samples enable row level security;

-- Everyone can only ever see or touch their own rows — including through the
-- publishable key that ships in the public page.
drop policy if exists stride_docs_own    on public.stride_docs;
drop policy if exists stride_samples_own on public.stride_samples;

create policy stride_docs_own on public.stride_docs
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy stride_samples_own on public.stride_samples
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Signed-in users work through the policies above; anonymous callers get nothing.
grant select, insert, update, delete on public.stride_docs, public.stride_samples to authenticated;
revoke all on public.stride_docs, public.stride_samples from anon;
