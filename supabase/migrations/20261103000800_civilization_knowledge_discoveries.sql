-- PROJECT ETHO: cumulative knowledge and cultural discoveries.
-- Apply after 20261103000700_border_snapshot_guard.sql.

create table if not exists public.civilization_knowledge (
  id uuid primary key default gen_random_uuid(),
  civilization_id uuid not null unique references public.civilizations(id) on delete cascade,
  knowledge_points numeric not null default 0,
  last_research_year integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.civilization_discoveries (
  id uuid primary key default gen_random_uuid(),
  civilization_id uuid not null references public.civilizations(id) on delete cascade,
  discovery_key text not null,
  name text not null,
  description text not null,
  discovered_year numeric not null,
  knowledge_cost numeric not null,
  created_at timestamptz not null default now(),
  unique(civilization_id,discovery_key)
);

alter table public.civilization_knowledge enable row level security;
alter table public.civilization_discoveries enable row level security;

drop policy if exists "creator all civilization knowledge" on public.civilization_knowledge;
create policy "creator all civilization knowledge" on public.civilization_knowledge
  for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all civilization discoveries" on public.civilization_discoveries;
create policy "creator all civilization discoveries" on public.civilization_discoveries
  for all to authenticated using(public.is_creator()) with check(public.is_creator());

create or replace function public.advance_civilization_knowledge(p_slug text default 'x-219b')
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  wid uuid; yr numeric; yr_int integer; civ record; knowledge record;
  pop integer; work_count integer; settlement_count integer;
  points_gained numeric; next_discovery record; discoveries_added integer := 0;
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  perform pg_advisory_xact_lock(hashtext(wid::text));
  select simulated_year into yr from public.get_world_status(p_slug);
  yr_int := floor(yr)::integer;

  select * into civ from public.civilizations where world_id=wid order by founded_year,created_at limit 1;
  if civ.id is null then return jsonb_build_object('advanced',false,'reason','No civilization exists yet.'); end if;

  insert into public.civilization_knowledge(civilization_id) values(civ.id) on conflict(civilization_id) do nothing;
  select * into knowledge from public.civilization_knowledge where civilization_id=civ.id for update;
  if yr_int <= knowledge.last_research_year then
    return jsonb_build_object('advanced',false,'reason','Knowledge was already advanced this year.','knowledge_points',knowledge.knowledge_points);
  end if;

  select count(*) into pop from public.citizens where world_id=wid and status='alive';
  select count(*) into work_count from public.citizen_work_log
    where world_id=wid and world_year>knowledge.last_research_year and world_year<=yr_int;
  select count(*) into settlement_count from public.settlements where world_id=wid and status='active';

  points_gained := least(5::numeric,(work_count*0.25)+(pop*0.08)+(settlement_count*0.2));
  update public.civilization_knowledge
  set knowledge_points=knowledge_points+points_gained,last_research_year=yr_int,updated_at=now()
  where civilization_id=civ.id returning * into knowledge;

  select catalog.* into next_discovery
  from (values
    (1,'fire_keeping','Reliable fire keeping','People learn to preserve embers and maintain a shared fire for warmth, light, and cooking.',4::numeric),
    (2,'stone_toolcraft','Improved stone toolcraft','Careful shaping produces more dependable cutting, scraping, and woodworking tools.',8::numeric),
    (3,'woven_containers','Woven containers','Fibres and flexible branches are woven into containers that help carry and store gathered resources.',13::numeric),
    (4,'cultivation','Deliberate plant cultivation','People begin tending useful plants near their homes and keeping track of seasonal growth.',19::numeric),
    (5,'pottery','Pottery and fired clay','Clay vessels become useful for carrying, storing, and preparing materials.',26::numeric),
    (6,'irrigation','Simple irrigation','Channels and managed water flow help nearby growing plots receive water more reliably.',34::numeric),
    (7,'metallurgy','Early metalworking','Experiments with naturally occurring metals introduce a new craft and specialist knowledge.',43::numeric),
    (8,'record_keeping','Shared record keeping','Marks and symbols begin to preserve quantities, agreements, and important community events.',53::numeric)
  ) as catalog(rank,discovery_key,name,description,knowledge_cost)
  where not exists(select 1 from public.civilization_discoveries d
    where d.civilization_id=civ.id and d.discovery_key=catalog.discovery_key)
  order by catalog.rank limit 1;

  if next_discovery.discovery_key is not null and knowledge.knowledge_points>=next_discovery.knowledge_cost then
    insert into public.civilization_discoveries(civilization_id,discovery_key,name,description,discovered_year,knowledge_cost)
    values(civ.id,next_discovery.discovery_key,next_discovery.name,next_discovery.description,yr,next_discovery.knowledge_cost)
    on conflict(civilization_id,discovery_key) do nothing;
    insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
    values(wid,yr,'discovery','A new discovery changes daily life',
      next_discovery.name||': '||next_discovery.description,
      jsonb_build_object('civilization_id',civ.id,'discovery_key',next_discovery.discovery_key,'knowledge_points',knowledge.knowledge_points));
    discoveries_added:=1;
  end if;

  return jsonb_build_object('advanced',true,'world_year',yr,'knowledge_points',knowledge.knowledge_points,
    'points_gained',points_gained,'discoveries_added',discoveries_added);
end;
$$;

grant execute on function public.advance_civilization_knowledge(text) to authenticated;
