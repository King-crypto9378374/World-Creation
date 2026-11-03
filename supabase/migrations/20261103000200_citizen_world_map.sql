-- PROJECT ETHO: persistent citizen positions and first simulation tick.
-- Run once in Supabase SQL Editor after the world foundation migration.
alter table public.citizens
  add column if not exists x numeric not null default 0.48,
  add column if not exists y numeric not null default 0.52,
  add column if not exists current_activity text not null default 'Resting near the settlement',
  add column if not exists last_simulated_year numeric not null default 1,
  add column if not exists last_moved_at timestamptz not null default now();

alter table public.prayers
  add column if not exists related_event_id uuid references public.world_events(id) on delete set null;

update public.citizens c
set x = coalesce(s.x,0.48), y = coalesce(s.y,0.52)
from public.settlements s
where c.settlement_id=s.id and c.x=0.48 and c.y=0.52;

create index if not exists citizens_world_location_idx on public.citizens(world_id,x,y);

-- A server-authoritative tick persists ages and small movements.
-- Coordinates are normalized to the fictional map (0..1), not real-world GPS.
create or replace function public.advance_world_simulation(p_slug text default 'x-219b')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  moved integer := 0;
begin
  if not public.is_creator() then
    raise exception 'Creator permission required';
  end if;

  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;

  select simulated_year into yr from public.get_world_status(p_slug);

  update public.citizens c
  set age_years = greatest(0, floor(yr - c.birth_year)::integer),
      x = greatest(0.03,least(0.97,
        coalesce((select s.x from public.settlements s where s.id=c.settlement_id),c.x)
        + sin(extract(epoch from now())/420 + (('x'||substr(replace(c.id::text,'-',''),1,8))::bit(32)::int % 1000)) * 0.012)),
      y = greatest(0.04,least(0.96,
        coalesce((select s.y from public.settlements s where s.id=c.settlement_id),c.y)
        + cos(extract(epoch from now())/510 + (('x'||substr(replace(c.id::text,'-',''),1,8))::bit(32)::int % 1000)) * 0.012)),
      current_activity = case
        when c.age_years < 5 then 'Playing and learning near the hearth'
        when c.age_years < 14 then 'Helping family and exploring nearby'
        when c.age_years > 65 then 'Resting and sharing knowledge'
        when 'adventurous'=any(c.traits) then 'Exploring the nearby land'
        when 'protective'=any(c.traits) then 'Watching over the settlement'
        when 'creative'=any(c.traits) then 'Making and improving tools'
        else 'Gathering, working, and socializing'
      end,
      last_simulated_year=yr,
      last_moved_at=now()
  where c.world_id=wid and c.status='alive';

  get diagnostics moved = row_count;
  return jsonb_build_object('world_year',yr,'citizens_updated',moved,'updated_at',now());
end;
$$;

grant execute on function public.advance_world_simulation(text) to authenticated;
