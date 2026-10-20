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

-- ── Crew board (added Oct 2026) ─────────────────────────────────────────────
-- Opt-in weekly totals shared with a small group. Someone creates a crew,
-- which is just a random code; friends join by entering it. You can only
-- read rows from your own crew, and only write your own row. Nothing but a
-- display name and this week's counts is stored here — no runs, HR or weight.
-- Safe to run again; the app hides the board until this table exists.

create table if not exists public.stride_crew (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  group_code text        not null check (group_code ~ '^[A-Z0-9]{10}$'),
  name       text        not null check (char_length(name) between 1 and 40),
  week_start date        not null,
  runs       int         not null default 0 check (runs between 0 and 50),
  minutes    int         not null default 0 check (minutes between 0 and 5000),
  miles      numeric(6,1) not null default 0 check (miles between 0 and 1000),
  streak     int         not null default 0 check (streak between 0 and 520),
  updated_at timestamptz not null default now()
);
create index if not exists stride_crew_group on public.stride_crew (group_code);

alter table public.stride_crew enable row level security;

-- The caller's own crew code. Security definer so the select policy can look
-- it up without the policy recursing into itself.
create or replace function public.stride_my_crew() returns text
  language sql stable security definer set search_path = public
  as $$ select group_code from public.stride_crew where user_id = (select auth.uid()) $$;
revoke all on function public.stride_my_crew() from public, anon;
grant execute on function public.stride_my_crew() to authenticated;

drop policy if exists stride_crew_read  on public.stride_crew;
drop policy if exists stride_crew_write on public.stride_crew;
create policy stride_crew_read on public.stride_crew
  for select to authenticated
  using (group_code = public.stride_my_crew());
create policy stride_crew_write on public.stride_crew
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.stride_crew to authenticated;
revoke all on public.stride_crew from anon;
