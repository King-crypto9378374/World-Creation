-- PROJECT ETHO: persistent world foundation
-- Apply with Supabase SQL Editor or: supabase db push
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Etho',
  role text not null default 'observer' check (role in ('creator','observer')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'Etho'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_creator()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'creator');
$$;

create table if not exists public.worlds (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text not null default '',
  started_at timestamptz not null default now(),
  paused_at timestamptz,
  accumulated_paused_seconds numeric not null default 0,
  time_ratio_seconds_per_year integer not null default 3600 check (time_ratio_seconds_per_year > 0),
  current_year numeric not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.worlds (slug, name, description)
values ('x-219b', 'The First World', 'A new humanity begins at the dawn of its history.')
on conflict (slug) do nothing;

create table if not exists public.settlements (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  name text not null,
  description text not null default '',
  founded_year numeric not null default 1,
  population integer not null default 0 check (population >= 0),
  biome text not null default 'river valley',
  x numeric not null default 0,
  y numeric not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

create table if not exists public.citizens (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  settlement_id uuid references public.settlements(id) on delete set null,
  full_name text not null,
  age_years integer not null default 18 check (age_years >= 0),
  birth_year numeric not null default 1,
  death_year numeric,
  status text not null default 'alive' check (status in ('alive','deceased')),
  personality jsonb not null default '{}'::jsonb,
  traits text[] not null default '{}',
  beliefs jsonb not null default '{}'::jsonb,
  ambitions text[] not null default '{}',
  relationships jsonb not null default '{}'::jsonb,
  family_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists citizens_world_status_idx on public.citizens(world_id, status);
create index if not exists citizens_settlement_idx on public.citizens(settlement_id);

create table if not exists public.citizen_memories (
  id uuid primary key default gen_random_uuid(),
  citizen_id uuid not null references public.citizens(id) on delete cascade,
  world_year numeric not null,
  memory_type text not null default 'life_event',
  content text not null,
  emotional_weight numeric not null default 0,
  source_event_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists citizen_memories_citizen_idx on public.citizen_memories(citizen_id, world_year desc);

create table if not exists public.prayers (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  citizen_id uuid not null references public.citizens(id) on delete cascade,
  message text not null,
  emotional_state text not null default 'hopeful',
  context text not null default '',
  world_year numeric not null,
  created_at timestamptz not null default now(),
  status text not null default 'unanswered' check (status in ('unanswered','answered','archived'))
);
create index if not exists prayers_inbox_idx on public.prayers(world_id, status, created_at desc);

create table if not exists public.prayer_responses (
  id uuid primary key default gen_random_uuid(),
  prayer_id uuid not null references public.prayers(id) on delete cascade,
  creator_id uuid not null references auth.users(id),
  message text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.world_events (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  world_year numeric not null,
  event_type text not null,
  title text not null,
  description text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists world_events_timeline_idx on public.world_events(world_id, world_year desc);

create table if not exists public.broadcasts (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  creator_id uuid not null references auth.users(id),
  message text not null,
  issued_at_year numeric not null,
  reach_status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- Authoritative time calculation. The browser never decides the world's year.
create or replace function public.get_world_status(p_slug text default 'x-219b')
returns table (
  id uuid, slug text, name text, simulated_year numeric,
  real_now timestamptz, started_at timestamptz,
  paused boolean, time_ratio_seconds_per_year integer
)
language sql stable security definer set search_path = public
as $$
  select w.id, w.slug, w.name,
    round((1 + greatest(0,
      (extract(epoch from (coalesce(w.paused_at, now()) - w.started_at))
       - w.accumulated_paused_seconds) / w.time_ratio_seconds_per_year
    ))::numeric, 6),
    now(), w.started_at, (w.paused_at is not null), w.time_ratio_seconds_per_year
  from public.worlds w where w.slug = p_slug;
$$;

alter table public.profiles enable row level security;
alter table public.worlds enable row level security;
alter table public.settlements enable row level security;
alter table public.citizens enable row level security;
alter table public.citizen_memories enable row level security;
alter table public.prayers enable row level security;
alter table public.prayer_responses enable row level security;
alter table public.world_events enable row level security;
alter table public.broadcasts enable row level security;

create policy "profile self read" on public.profiles for select to authenticated using (id = auth.uid() or public.is_creator());
create policy "profile self update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and role = 'observer');
create policy "creator read worlds" on public.worlds for select to authenticated using (public.is_creator());
create policy "creator update worlds" on public.worlds for update to authenticated using (public.is_creator()) with check (public.is_creator());
create policy "creator all settlements" on public.settlements for all to authenticated using (public.is_creator()) with check (public.is_creator());
create policy "creator all citizens" on public.citizens for all to authenticated using (public.is_creator()) with check (public.is_creator());
create policy "creator all memories" on public.citizen_memories for all to authenticated using (public.is_creator()) with check (public.is_creator());
create policy "creator read prayers" on public.prayers for select to authenticated using (public.is_creator());
create policy "creator update prayers" on public.prayers for update to authenticated using (public.is_creator()) with check (public.is_creator());
create policy "creator read responses" on public.prayer_responses for select to authenticated using (public.is_creator());
create policy "creator write responses" on public.prayer_responses for insert to authenticated with check (public.is_creator() and creator_id = auth.uid());
create policy "creator read events" on public.world_events for select to authenticated using (public.is_creator());
create policy "creator write events" on public.world_events for insert to authenticated with check (public.is_creator());
create policy "creator all broadcasts" on public.broadcasts for all to authenticated using (public.is_creator()) with check (public.is_creator());

grant execute on function public.get_world_status(text) to authenticated;
grant execute on function public.is_creator() to authenticated;

-- The initial settlement and starter population are inserted by the simulation
-- initializer after the first creator account is promoted. No fake prayers are seeded.
