-- PROJECT ETHO: persistent society simulation engine
-- Apply after 20261103000200_citizen_world_map.sql.
create table if not exists public.world_locations (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  settlement_id uuid references public.settlements(id) on delete set null,
  name text not null,
  location_type text not null default 'landmark',
  biome text not null default 'grassland',
  x numeric not null check (x between 0 and 1),
  y numeric not null check (y between 0 and 1),
  description text not null default '',
  created_at timestamptz not null default now(),
  unique(world_id,name)
);
create table if not exists public.citizen_journeys (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  citizen_id uuid not null references public.citizens(id) on delete cascade,
  origin_location_id uuid not null references public.world_locations(id),
  destination_location_id uuid not null references public.world_locations(id),
  started_year numeric not null,
  expected_arrival_year numeric not null,
  status text not null default 'travelling' check(status in ('travelling','arrived','cancelled')),
  purpose text not null default 'exploration',
  created_at timestamptz not null default now()
);
create index if not exists citizen_journeys_active_idx on public.citizen_journeys(citizen_id,status);
create table if not exists public.citizen_partnerships (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  citizen_a_id uuid not null references public.citizens(id) on delete cascade,
  citizen_b_id uuid not null references public.citizens(id) on delete cascade,
  formed_year numeric not null,
  household_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  check(citizen_a_id <> citizen_b_id),
  unique(citizen_a_id,citizen_b_id)
);
create table if not exists public.citizen_family_links (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  parent_id uuid not null references public.citizens(id) on delete cascade,
  child_id uuid not null references public.citizens(id) on delete cascade,
  relationship text not null default 'parent',
  created_at timestamptz not null default now(),
  unique(parent_id,child_id)
);
create table if not exists public.world_society_state (
  world_id uuid primary key references public.worlds(id) on delete cascade,
  food numeric not null default 100,
  fresh_water numeric not null default 100,
  shelter_capacity integer not null default 20,
  stability numeric not null default 75,
  last_tick_year numeric not null default 1,
  last_birth_cycle integer not null default 0,
  last_resource_event text,
  updated_at timestamptz not null default now()
);

alter table public.citizens
  add column if not exists parent_a_id uuid references public.citizens(id) on delete set null,
  add column if not exists parent_b_id uuid references public.citizens(id) on delete set null,
  add column if not exists household_id uuid,
  add column if not exists last_journey_year numeric not null default 1,
  add column if not exists needs jsonb not null default '{"food":100,"water":100,"safety":100,"belonging":100}'::jsonb;

create index if not exists citizen_family_parent_idx on public.citizens(parent_a_id,parent_b_id);
create index if not exists citizen_journey_due_idx on public.citizens(world_id,last_journey_year);

do $$
declare wid uuid;
begin
  select id into wid from public.worlds where slug='x-219b';
  insert into public.world_locations(world_id,settlement_id,name,location_type,biome,x,y,description)
  select wid,s.id,s.name,'settlement',s.biome,s.x,s.y,s.description
  from public.settlements s where s.world_id=wid
  on conflict(world_id,name) do nothing;

  insert into public.world_locations(world_id,name,location_type,biome,x,y,description) values
    (wid,'River Bend','waterway','river valley',0.68,0.38,'A bend in the freshwater river, with shallow banks and animal tracks.'),
    (wid,'Northern Grove','forest','woodland',0.29,0.20,'A stand of trees with edible plants, shade, and nesting birds.'),
    (wid,'Stone Ridge','highland','rocky hills',0.78,0.68,'A low ridge overlooking the valley, with exposed stone and a wide view.'),
    (wid,'Southern Marsh','wetland','marsh',0.31,0.78,'A marshy lowland where reeds grow thick beside still water.')
  on conflict(world_id,name) do nothing;

  insert into public.world_society_state(world_id) values(wid)
  on conflict(world_id) do nothing;
end $$;

alter table public.world_locations enable row level security;
alter table public.citizen_journeys enable row level security;
alter table public.citizen_partnerships enable row level security;
alter table public.citizen_family_links enable row level security;
alter table public.world_society_state enable row level security;

drop policy if exists "creator all locations" on public.world_locations;
create policy "creator all locations" on public.world_locations for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all journeys" on public.citizen_journeys;
create policy "creator all journeys" on public.citizen_journeys for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all partnerships" on public.citizen_partnerships;
create policy "creator all partnerships" on public.citizen_partnerships for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all family links" on public.citizen_family_links;
create policy "creator all family links" on public.citizen_family_links for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator read society state" on public.world_society_state;
create policy "creator read society state" on public.world_society_state for select to authenticated using(public.is_creator());

create or replace function public.advance_world_simulation(p_slug text default 'x-219b')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  prev_yr numeric;
  elapsed numeric;
  pop integer;
  pair record;
  child_id uuid;
  child_name text;
  birth_cycle integer;
  food_now numeric;
  water_now numeric;
  journey_count integer := 0;
  birth_count integer := 0;
  event_count integer := 0;
  names text[] := array['Asha','Riven','Tali','Soren','Elia','Nerin','Kael','Mara','Oren','Liora','Bren','Anya'];
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  perform pg_advisory_xact_lock(hashtext(wid::text));
  select simulated_year into yr from public.get_world_status(p_slug);
  insert into public.world_society_state(world_id) values(wid) on conflict(world_id) do nothing;
  select last_tick_year,food,fresh_water into prev_yr,food_now,water_now
  from public.world_society_state where world_id=wid for update;
  elapsed := greatest(0,least(1,yr-prev_yr));

  update public.citizens c
  set age_years=greatest(0,floor(yr-c.birth_year)::integer),
      last_simulated_year=yr
  where c.world_id=wid and c.status='alive';

  -- Complete journeys whose arrival year has passed.
  update public.citizen_journeys j set status='arrived'
  where j.world_id=wid and j.status='travelling' and j.expected_arrival_year<=yr;
  get diagnostics journey_count=row_count;

  -- Persist interpolated travel positions; the route is between named map locations.
  update public.citizens c
  set x=round((o.x+(d.x-o.x)*greatest(0,least(1,(yr-j.started_year)/greatest(.0001,j.expected_arrival_year-j.started_year))))::numeric,6),
      y=round((o.y+(d.y-o.y)*greatest(0,least(1,(yr-j.started_year)/greatest(.0001,j.expected_arrival_year-j.started_year))))::numeric,6),
      current_activity='Travelling to '||d.name
  from public.citizen_journeys j
  join public.world_locations o on o.id=j.origin_location_id
  join public.world_locations d on d.id=j.destination_location_id
  where j.citizen_id=c.id and j.status='travelling' and j.world_id=wid;

  -- Citizens who arrive take up an activity at the destination.
  update public.citizens c
  set x=l.x,y=l.y,
      settlement_id=coalesce(l.settlement_id,c.settlement_id),
      current_activity='Exploring '||l.name
  from public.citizen_journeys j
  join public.world_locations l on l.id=j.destination_location_id
  where j.citizen_id=c.id and j.status='arrived'
    and c.world_id=wid and c.current_activity like 'Travelling to %'
    and j.expected_arrival_year<=yr;

  -- Start purposeful journeys for a rotating subset of adults every two simulated years.
  with candidates as (
    select c.id,c.x,c.y,c.settlement_id,c.traits,
      row_number() over(order by md5(c.id::text||floor(yr)::text)) as rn
    from public.citizens c
    where c.world_id=wid and c.status='alive' and c.age_years>=16
      and yr-c.last_journey_year>=2
      and not exists(select 1 from public.citizen_journeys j where j.citizen_id=c.id and j.status='travelling')
  ), destinations as (
    select l.id,l.name,l.x,l.y,
      row_number() over(order by md5(l.id::text||floor(yr)::text)) as rn
    from public.world_locations l where l.world_id=wid
  )
  insert into public.citizen_journeys(world_id,citizen_id,origin_location_id,destination_location_id,started_year,expected_arrival_year,purpose)
  select wid,c.id,
    (select ol.id from public.world_locations ol where ol.world_id=wid order by power(ol.x-c.x,2)+power(ol.y-c.y,2) limit 1),
    d.id,yr,yr+(0.35+((c.rn%5)*0.18)),
    case when 'adventurous'=any(c.traits) then 'exploration' else 'gathering' end
  from candidates c
  join destinations d on d.rn=((c.rn % (select count(*) from destinations))+1)
  where c.rn%3=1
  on conflict do nothing;
  get diagnostics journey_count=row_count;

  update public.citizens c set last_journey_year=yr
  where c.world_id=wid and c.status='alive' and c.age_years>=16
    and exists(select 1 from public.citizen_journeys j where j.citizen_id=c.id and j.started_year=yr);

  -- Establish non-romantic household partnerships between eligible adult citizens.
  insert into public.citizen_partnerships(world_id,citizen_a_id,citizen_b_id,formed_year,household_id)
  select wid,a.id,b.id,yr,gen_random_uuid()
  from public.citizens a
  join lateral (
    select c.id from public.citizens c
    where c.world_id=wid and c.status='alive' and c.age_years between 20 and 38
      and c.id>a.id and c.settlement_id is not distinct from a.settlement_id
    order by md5(c.id::text||a.id::text) limit 1
  ) b on true
  where a.world_id=wid and a.status='alive' and a.age_years between 20 and 38
    and not exists(select 1 from public.citizen_partnerships p where p.citizen_a_id=a.id or p.citizen_b_id=a.id)
  order by md5(a.id::text||floor(yr)::text)
  limit 1
  on conflict(citizen_a_id,citizen_b_id) do nothing;

  -- One new child per four-year cycle, with both caregivers recorded in the family tree.
  birth_cycle:=greatest(0,floor((yr-1)/4)::integer);
  if birth_cycle>(select last_birth_cycle from public.world_society_state where world_id=wid) then
    select p.* into pair
    from public.citizen_partnerships p
    join public.citizens a on a.id=p.citizen_a_id
    join public.citizens b on b.id=p.citizen_b_id
    where p.world_id=wid and a.status='alive' and b.status='alive'
      and a.age_years between 20 and 45 and b.age_years between 20 and 45
    order by p.formed_year,p.created_at limit 1;
    if pair.id is not null then
      child_id:=gen_random_uuid();
      child_name:=names[(birth_cycle % array_length(names,1))+1];
      if exists(select 1 from public.citizens where world_id=wid and full_name=child_name) then
        child_name:=child_name||'-'||(birth_cycle+1)::text;
      end if;
      insert into public.citizens(world_id,settlement_id,full_name,age_years,birth_year,status,traits,personality,beliefs,ambitions,household_id,parent_a_id,parent_b_id,family_id,x,y,current_activity)
      select wid,a.settlement_id,child_name,0,yr,'alive',array['curious','observant'],'{"temperament":"developing"}'::jsonb,'{}'::jsonb,array['learn about the world'],pair.household_id,a.id,b.id,pair.household_id,
        (a.x+b.x)/2,(a.y+b.y)/2,'Being cared for by family'
      from public.citizens a join public.citizens b on b.id=pair.citizen_b_id
      where a.id=pair.citizen_a_id;
      insert into public.citizen_family_links(world_id,parent_id,child_id) values
        (wid,pair.citizen_a_id,child_id),(wid,pair.citizen_b_id,child_id);
      update public.citizens set household_id=pair.household_id,family_id=pair.household_id
      where id in(pair.citizen_a_id,pair.citizen_b_id);
      insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
      values(wid,yr,'birth','A new child joins the hearth',child_name||' has been born into a household at the First Hearth.',
        jsonb_build_object('citizen_id',child_id,'parent_a_id',pair.citizen_a_id,'parent_b_id',pair.citizen_b_id));
      insert into public.prayers(world_id,citizen_id,message,emotional_state,context,world_year,related_event_id)
      values(wid,pair.citizen_a_id,'A new child has joined our household. May they grow with kindness and find a place in this world.',
        'hopeful','A birth has changed this household; the family is adjusting to caring for a new child.',yr,
        (select id from public.world_events where world_id=wid and event_type='birth' order by created_at desc limit 1));
      birth_count:=1;
      update public.world_society_state set last_birth_cycle=birth_cycle where world_id=wid;
    end if;
  end if;

  -- Resource pressure is accumulated from population and partly offset by gathering.
  select count(*) into pop from public.citizens where world_id=wid and status='alive';
  food_now:=greatest(0,food_now-(pop*elapsed*0.035)+(pop*elapsed*0.025));
  water_now:=greatest(0,water_now-(pop*elapsed*0.025)+(pop*elapsed*0.018));
  update public.world_society_state
  set food=food_now,fresh_water=water_now,
      stability=greatest(0,least(100,stability+case when food_now<20 or water_now<20 then -elapsed*2 else elapsed*.15 end)),
      last_tick_year=greatest(last_tick_year,yr),updated_at=now()
  where world_id=wid;

  -- A concrete shortage creates a world event and a prayer linked to that event.
  if food_now<20 and not exists(select 1 from public.world_events where world_id=wid and event_type='food_shortage' and world_year>yr-3) then
    insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
    values(wid,yr,'food_shortage','Food stores are running low','The settlement stores are dwindling. Gathering parties must travel farther, and families are becoming concerned.',
      jsonb_build_object('food',food_now,'population',pop));
    insert into public.prayers(world_id,citizen_id,message,emotional_state,context,world_year,related_event_id)
    select wid,c.id,'Our food stores are growing thin. The gathering parties return with less each time. Please guide us toward a safer source of food.',
      'worried','Food stores are below the society threshold; this citizen lives in the affected settlement.',yr,
      (select id from public.world_events where world_id=wid and event_type='food_shortage' order by created_at desc limit 1)
    from public.citizens c where c.world_id=wid and c.status='alive' order by c.age_years desc limit 1;
    event_count:=event_count+1;
  elsif water_now<20 and not exists(select 1 from public.world_events where world_id=wid and event_type='water_shortage' and world_year>yr-3) then
    insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
    values(wid,yr,'water_shortage','The river is harder to reach','The community is spending more time finding clean water, affecting daily work and morale.',
      jsonb_build_object('fresh_water',water_now,'population',pop));
    insert into public.prayers(world_id,citizen_id,message,emotional_state,context,world_year,related_event_id)
    select wid,c.id,'The water is harder to find, and our days are being spent searching. We are worried about the children and elders.',
      'afraid','Fresh water is below the society threshold and daily routines are being disrupted.',yr,
      (select id from public.world_events where world_id=wid and event_type='water_shortage' order by created_at desc limit 1)
    from public.citizens c where c.world_id=wid and c.status='alive' order by c.age_years desc limit 1;
    event_count:=event_count+1;
  end if;

  update public.citizens c
  set needs=jsonb_build_object(
    'food',greatest(0,least(100,food_now)),
    'water',greatest(0,least(100,water_now)),
    'safety',greatest(0,least(100,(select stability from public.world_society_state where world_id=wid))),
    'belonging',greatest(20,least(100,coalesce((c.needs->>'belonging')::numeric,80)))
  )
  where c.world_id=wid and c.status='alive';

  return jsonb_build_object('world_year',yr,'population',pop+birth_count,'journeys_started',journey_count,
    'births',birth_count,'events_created',event_count,'food',food_now,'fresh_water',water_now);
end;
$$;

grant execute on function public.advance_world_simulation(text) to authenticated;
