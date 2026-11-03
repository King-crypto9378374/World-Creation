-- PROJECT ETHO: autonomous work, resource gathering, construction, and settlement growth.
-- Apply after 20261103000400_geography_civilizations_environment.sql.

alter table public.world_society_state
  add column if not exists building_materials numeric not null default 20,
  add column if not exists last_development_year integer not null default 0;

create table if not exists public.world_buildings (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  settlement_id uuid references public.settlements(id) on delete set null,
  building_type text not null check (building_type in ('home','farm','workshop','storehouse','well')),
  name text not null,
  x numeric not null check (x between 0 and 1),
  y numeric not null check (y between 0 and 1),
  built_year numeric not null,
  capacity integer not null default 0,
  condition numeric not null default 100 check (condition between 0 and 100),
  created_at timestamptz not null default now()
);
create index if not exists world_buildings_world_idx on public.world_buildings(world_id);

create table if not exists public.citizen_work_log (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  citizen_id uuid not null references public.citizens(id) on delete cascade,
  world_year numeric not null,
  activity text not null,
  output jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists citizen_work_log_world_year_idx on public.citizen_work_log(world_id,world_year desc);

alter table public.world_buildings enable row level security;
alter table public.citizen_work_log enable row level security;
drop policy if exists "creator all world buildings" on public.world_buildings;
create policy "creator all world buildings" on public.world_buildings
  for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all citizen work log" on public.citizen_work_log;
create policy "creator all citizen work log" on public.citizen_work_log
  for all to authenticated using(public.is_creator()) with check(public.is_creator());

create or replace function public.advance_civilization_development(p_slug text default 'x-219b')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  yr_int integer;
  prev_year integer;
  pop integer;
  worker record;
  roll integer;
  activity text;
  food_gain numeric := 0;
  water_gain numeric := 0;
  material_gain numeric := 0;
  buildings_added integer := 0;
  new_settlement_id uuid;
  base_settlement record;
  assigned integer := 0;
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  perform pg_advisory_xact_lock(hashtext(wid::text));
  select simulated_year into yr from public.get_world_status(p_slug);
  yr_int := floor(yr)::integer;

  insert into public.world_society_state(world_id) values(wid) on conflict(world_id) do nothing;
  select last_development_year into prev_year
  from public.world_society_state where world_id=wid for update;
  if yr_int <= prev_year then
    return jsonb_build_object('advanced',false,'world_year',yr,'reason','This simulated year has already been developed.');
  end if;

  select count(*) into pop from public.citizens where world_id=wid and status='alive';

  -- Every adult receives a persistent yearly occupation, with output recorded in the shared economy.
  for worker in
    select id,full_name,age_years,traits,x,y,settlement_id
    from public.citizens
    where world_id=wid and status='alive' and age_years>=14
    order by md5(id::text || ':' || yr_int::text)
  loop
    roll := mod(abs(hashtextextended(worker.id::text || ':' || yr_int::text,0)),6)::integer;
    if roll=0 then
      activity := 'Foraging for edible plants and seasonal food';
      food_gain := food_gain + 2.4;
    elsif roll=1 then
      activity := 'Collecting and carrying fresh water';
      water_gain := water_gain + 2.2;
    elsif roll=2 then
      activity := 'Gathering fallen timber and useful branches';
      material_gain := material_gain + 2.0;
    elsif roll=3 then
      activity := 'Gathering stone and shaping basic tools';
      material_gain := material_gain + 1.6;
    elsif roll=4 then
      activity := 'Tending shared plots and cultivating food';
      food_gain := food_gain + 3.2;
    else
      activity := 'Crafting tools, baskets, and household goods';
      material_gain := material_gain + 1.2;
    end if;

    update public.citizens
    set current_activity=activity,
        needs=jsonb_set(
          jsonb_set(coalesce(needs,'{}'::jsonb),'{belonging}',
            to_jsonb(least(100,greatest(20,coalesce((needs->>'belonging')::numeric,75)+1))),true),
          '{food}',to_jsonb(least(100,greatest(0,coalesce((needs->>'food')::numeric,75)+3))),true)
    where id=worker.id;

    insert into public.citizen_work_log(world_id,citizen_id,world_year,activity,output)
    values(wid,worker.id,yr,activity,
      case when roll in (0,4) then jsonb_build_object('food',case when roll=0 then 2.4 else 3.2 end)
           when roll=1 then jsonb_build_object('fresh_water',2.2)
           else jsonb_build_object('building_materials',case when roll=2 then 2.0 else 1.6 end) end);
  end loop;

  update public.world_society_state
  set food=least(500,food+food_gain),
      fresh_water=least(500,fresh_water+water_gain),
      building_materials=least(500,building_materials+material_gain),
      updated_at=now()
  where world_id=wid;

  -- Build shared homes when the current shelter capacity is no longer sufficient.
  select s.* into base_settlement
  from public.settlements s where s.world_id=wid and s.status='active'
  order by s.founded_year,s.created_at limit 1;

  if base_settlement.id is not null then
    select count(*) into pop from public.citizens where world_id=wid and status='alive';
    while (select shelter_capacity from public.world_society_state where world_id=wid) < pop
      and (select building_materials from public.world_society_state where world_id=wid) >= 8
      and buildings_added < 3
    loop
      insert into public.world_buildings(world_id,settlement_id,building_type,name,x,y,built_year,capacity)
      values(wid,base_settlement.id,'home','Community dwelling '||
        (select count(*)+1 from public.world_buildings where world_id=wid and building_type='home'),
        greatest(.02,least(.98,base_settlement.x+(buildings_added*.025))),
        greatest(.02,least(.98,base_settlement.y+(buildings_added*.02))),yr,4);
      update public.world_society_state
      set shelter_capacity=shelter_capacity+4,building_materials=building_materials-8
      where world_id=wid;
      buildings_added := buildings_added+1;
    end loop;

    -- A farm is added once the community has spare materials and enough people to tend it.
    if pop>=5 and not exists(select 1 from public.world_buildings where world_id=wid and building_type='farm')
       and (select building_materials from public.world_society_state where world_id=wid)>=6 then
      insert into public.world_buildings(world_id,settlement_id,building_type,name,x,y,built_year,capacity)
      values(wid,base_settlement.id,'farm','First shared growing plots',
        greatest(.02,least(.98,base_settlement.x+.055)),
        greatest(.02,least(.98,base_settlement.y+.035)),yr,6);
      update public.world_society_state set building_materials=building_materials-6 where world_id=wid;
      buildings_added := buildings_added+1;
    end if;
  end if;

  -- A second village can emerge when population and material reserves can support it.
  if yr_int>=4 and pop>=10
     and (select count(*) from public.settlements where world_id=wid and status='active')=1
     and (select building_materials from public.world_society_state where world_id=wid)>=24
     and base_settlement.id is not null then
    insert into public.settlements(world_id,name,description,founded_year,population,biome,x,y,status)
    values(wid,'Riverstead','A small daughter settlement founded by families seeking nearby fields and new ground.',
      yr,0,base_settlement.biome,
      greatest(.08,least(.92,base_settlement.x+.19)),
      greatest(.08,least(.92,base_settlement.y+.13)),'active')
    returning id into new_settlement_id;

    update public.citizens c set settlement_id=new_settlement_id,
      x=greatest(.08,least(.92,base_settlement.x+.19)),
      y=greatest(.08,least(.92,base_settlement.y+.13)),
      current_activity='Establishing the new settlement of Riverstead'
    where c.id in (
      select id from public.citizens
      where world_id=wid and status='alive' and age_years>=18
        and settlement_id=base_settlement.id
      order by md5(id::text||':riverstead:'||yr_int::text) limit 3
    );
    get diagnostics assigned=row_count;
    update public.settlements set population=assigned where id=new_settlement_id;
    insert into public.world_locations(world_id,settlement_id,name,location_type,biome,x,y,description)
    values(wid,new_settlement_id,'Riverstead','settlement',base_settlement.biome,
      greatest(.08,least(.92,base_settlement.x+.19)),
      greatest(.08,least(.92,base_settlement.y+.13)),
      'A growing village founded by citizens who carried tools and supplies into new land.')
    on conflict(world_id,name) do nothing;
    insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
    values(wid,yr,'settlement_founded','A new settlement takes root',
      'A small group has established Riverstead beyond the original hearth, beginning the first expansion of settled life.',
      jsonb_build_object('settlement_id',new_settlement_id,'founders',assigned));
    update public.world_society_state set building_materials=building_materials-24 where world_id=wid;
  end if;

  update public.settlements s set population=(
    select count(*) from public.citizens c
    where c.settlement_id=s.id and c.status='alive'
  ) where s.world_id=wid;

  update public.world_society_state
  set last_development_year=yr_int,updated_at=now()
  where world_id=wid;

  return jsonb_build_object(
    'advanced',true,'world_year',yr,'workers',(
      select count(*) from public.citizens where world_id=wid and status='alive' and age_years>=14
    ),'food_gathered',food_gain,'water_gathered',water_gain,
    'materials_gathered',material_gain,'buildings_added',buildings_added,
    'settlement_founded',new_settlement_id is not null
  );
end;
$$;

grant execute on function public.advance_civilization_development(text) to authenticated;
