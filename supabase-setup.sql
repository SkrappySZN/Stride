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

-- ── Weigh-in inbox (added Nov 2026) ─────────────────────────────────────────
-- A private key lets a script or Claude add weigh-ins without signing in. Only
-- the key's hash is stored. The key can add to the inbox and nothing else: it
-- can't read anything. The app moves what's waiting into the doc on open and
-- deletes it, because the doc itself is written compare-and-set by the app.
-- Safe to run again; the app says "almost ready" until these exist.

create table if not exists public.stride_keys (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  key_hash   text        not null unique check (key_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.stride_inbox (
  id         bigint      generated always as identity primary key,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  kind       text        not null,
  data       jsonb       not null,
  created_at timestamptz not null default now(),
  constraint stride_inbox_size check (pg_column_size(data) < 2000)
);
create index if not exists stride_inbox_user on public.stride_inbox (user_id);

alter table public.stride_keys  enable row level security;
alter table public.stride_inbox enable row level security;

drop policy if exists stride_keys_own  on public.stride_keys;
drop policy if exists stride_inbox_read on public.stride_inbox;
drop policy if exists stride_inbox_del  on public.stride_inbox;
create policy stride_keys_own on public.stride_keys
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy stride_inbox_read on public.stride_inbox
  for select to authenticated using ((select auth.uid()) = user_id);
create policy stride_inbox_del on public.stride_inbox
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.stride_keys, public.stride_inbox from anon, authenticated;
grant select, insert, update, delete on public.stride_keys to authenticated;
grant select, delete on public.stride_inbox to authenticated;

-- The one way in with a key. Security definer because the caller has no session;
-- it answers false for an unknown key and writes only to that key's owner.
create or replace function public.stride_inbox_add(p_key text, p_date date, p_lbs numeric, p_when text default 'am', p_note text default null)
  returns boolean language plpgsql security definer set search_path = public
  as $$
declare uid uuid;
begin
  select user_id into uid from public.stride_keys
    where key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex');
  if uid is null then return false; end if;
  if p_lbs is null or p_lbs <= 50 or p_lbs >= 600 then raise exception 'weight out of range'; end if;
  if p_when is null or p_when not in ('am', 'pm') then raise exception 'when must be am or pm'; end if;
  if p_date is null or p_date < current_date - 400 or p_date > current_date + 1 then raise exception 'date out of range'; end if;
  if char_length(coalesce(p_note, '')) > 80 then raise exception 'note too long'; end if;
  if (select count(*) from public.stride_inbox where user_id = uid) >= 200 then raise exception 'inbox full'; end if;
  insert into public.stride_inbox (user_id, kind, data) values (uid, 'weight',
    jsonb_strip_nulls(jsonb_build_object('date', p_date, 'lbs', p_lbs, 'when', p_when, 'note', nullif(trim(p_note), ''))));
  return true;
end $$;
revoke all on function public.stride_inbox_add(text, date, numeric, text, text) from public;
grant execute on function public.stride_inbox_add(text, date, numeric, text, text) to anon, authenticated;

-- ── Food in the inbox (added Nov 2026) ──────────────────────────────────────
-- The same key can also add a food entry (name, calories, protein). Safe to run again.

alter table public.stride_inbox drop constraint if exists stride_inbox_kind_check;
alter table public.stride_inbox add constraint stride_inbox_kind_check check (kind in ('weight', 'food'));

create or replace function public.stride_food_add(p_key text, p_date date, p_name text, p_cal numeric, p_pro numeric)
  returns boolean language plpgsql security definer set search_path = public
  as $$
declare uid uuid;
begin
  select user_id into uid from public.stride_keys
    where key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex');
  if uid is null then return false; end if;
  if char_length(trim(coalesce(p_name, ''))) not between 1 and 60 then raise exception 'name must be 1–60 characters'; end if;
  if p_cal is null or p_cal < 0 or p_cal > 5000 then raise exception 'calories out of range'; end if;
  if p_pro is null or p_pro < 0 or p_pro > 400 then raise exception 'protein out of range'; end if;
  if p_date is null or p_date < current_date - 400 or p_date > current_date + 1 then raise exception 'date out of range'; end if;
  if (select count(*) from public.stride_inbox where user_id = uid) >= 200 then raise exception 'inbox full'; end if;
  insert into public.stride_inbox (user_id, kind, data) values (uid, 'food',
    jsonb_build_object('date', p_date, 'name', trim(p_name), 'cal', round(p_cal), 'pro', round(p_pro)));
  return true;
end $$;
revoke all on function public.stride_food_add(text, date, text, numeric, numeric) from public;
grant execute on function public.stride_food_add(text, date, text, numeric, numeric) to anon, authenticated;
